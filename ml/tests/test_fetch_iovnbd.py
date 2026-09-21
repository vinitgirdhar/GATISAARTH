"""Offline tests for the IO-VNBD fetch tool: pointer parsing, subset selection,
verification and the retry/resume logic (a fake `fetch` replaces the network)."""
import hashlib

import pytest

from ml.src.dataset import fetch_iovnbd as f

CAT = "Synchronised V abd S datasets/Categorised IOVNB Dataset"
UNCAT = "Synchronised V abd S datasets/Uncategorised IOVNB Dataset"
UNSYNC = "Unsynchronised V and S Dataset/Uncategorised IOVNB (V and S) Dataset"


def pointer_text(data: bytes) -> str:
    return ("version https://git-lfs.github.com/spec/v1\n"
            f"oid sha256:{hashlib.sha256(data).hexdigest()}\nsize {len(data)}\n")


def make_tree(root):
    files = {
        f"{CAT}/M (Driver B)/S-M.csv": b"a,b\n1,2\n",
        f"{CAT}/M (Driver B)/V-M.csv": b"c,d\n3,4\n",
        f"{CAT}/M (Driver B)/V-M.JPG": b"jpgbytes",
        f"{UNCAT}/S-Dataset/S-M.csv": b"x\n",
        f"{UNSYNC}/S-Dataset/S-T1.csv": b"y\n",
        "Synchronised V abd S datasets.zip": b"zipbytes",
        "README.md": b"# not a pointer\n",
    }
    for rel, data in files.items():
        p = root / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(pointer_text(data) if rel != "README.md" else data.decode())
    return files


def test_parse_pointer_ok():
    oid, size = f.parse_pointer(pointer_text(b"hello"))
    assert oid == hashlib.sha256(b"hello").hexdigest() and size == 5


@pytest.mark.parametrize("bad", ["# a real readme\n", "", "version https://git-lfs.github.com/spec/v1\noid sha256:xyz\nsize 3\n",
                                 "version https://git-lfs.github.com/spec/v1\noid sha256:" + "a" * 64 + "\n"])
def test_parse_pointer_rejects(bad):
    with pytest.raises(ValueError):
        f.parse_pointer(bad)


def test_discover_subsets(tmp_path):
    make_tree(tmp_path)
    rels = lambda **kw: sorted(p.rel for p in f.discover(tmp_path, **kw))
    assert rels(subset="sync-categorised") == [f"{CAT}/M (Driver B)/S-M.csv", f"{CAT}/M (Driver B)/V-M.csv"]
    assert len(rels(subset="sync-all")) == 3
    assert len(rels(subset="all")) == 4  # zip never selected, README is not a pointer
    assert len(rels(subset="sync-categorised", include_images=True)) == 3


def test_url_encoding():
    url = f.url_for("A B/M (Driver B)/S-M.csv")
    assert url == f.BASE_URL + "A%20B/M%20(Driver%20B)/S-M.csv"


def test_verify(tmp_path):
    data = b"0123456789"
    ptr = f.Pointer("x.csv", hashlib.sha256(data).hexdigest(), len(data))
    p = tmp_path / "x.csv"
    assert not f.verify(p, ptr)
    p.write_bytes(data)
    assert f.verify(p, ptr)
    p.write_bytes(b"0123456780")  # same size, wrong hash
    assert not f.verify(p, ptr)
    p.write_bytes(b"short")
    assert not f.verify(p, ptr)


def fake_server(data: bytes, corrupt_first=False, honour_range=True):
    calls = []

    def fetch(url, offset):
        calls.append(offset)
        body = data[offset:] if honour_range else data
        if corrupt_first and len(calls) == 1:
            body = b"X" * len(body)
        status = 206 if (offset and honour_range) else 200
        return status, iter([body[i:i + 4] for i in range(0, len(body), 4)])
    return fetch, calls


def test_download_ok_then_skip(tmp_path):
    data = b"payload-bytes-0123456789"
    ptr = f.Pointer("d/x.csv", hashlib.sha256(data).hexdigest(), len(data))
    fetch, calls = fake_server(data)
    assert f.download_one(ptr, tmp_path, fetch, retries=2, sleep=lambda s: None) == "downloaded"
    assert (tmp_path / "d/x.csv").read_bytes() == data and not (tmp_path / "d/x.csv.part").exists()
    assert f.download_one(ptr, tmp_path, fetch, retries=2, sleep=lambda s: None) == "skipped"
    assert len(calls) == 1


def test_download_redownloads_after_corruption(tmp_path):
    data = b"payload-bytes-0123456789"
    ptr = f.Pointer("x.csv", hashlib.sha256(data).hexdigest(), len(data))
    fetch, calls = fake_server(data, corrupt_first=True)
    assert f.download_one(ptr, tmp_path, fetch, retries=3, sleep=lambda s: None) == "downloaded"
    assert (tmp_path / "x.csv").read_bytes() == data and len(calls) == 2


def test_download_resumes_partial_file(tmp_path):
    data = b"payload-bytes-0123456789"
    ptr = f.Pointer("x.csv", hashlib.sha256(data).hexdigest(), len(data))
    (tmp_path / "x.csv.part").write_bytes(data[:10])
    fetch, calls = fake_server(data)
    assert f.download_one(ptr, tmp_path, fetch, retries=2, sleep=lambda s: None) == "downloaded"
    assert calls == [10] and (tmp_path / "x.csv").read_bytes() == data


def test_download_server_ignores_range(tmp_path):
    data = b"payload-bytes-0123456789"
    ptr = f.Pointer("x.csv", hashlib.sha256(data).hexdigest(), len(data))
    (tmp_path / "x.csv.part").write_bytes(data[:10])
    fetch, _ = fake_server(data, honour_range=False)
    assert f.download_one(ptr, tmp_path, fetch, retries=2, sleep=lambda s: None) == "downloaded"
    assert (tmp_path / "x.csv").read_bytes() == data


def test_download_gives_up(tmp_path):
    data = b"payload"
    ptr = f.Pointer("x.csv", hashlib.sha256(data).hexdigest(), len(data))

    def bad(url, offset):
        return 200, iter([b"WRONG!!"])
    out = f.download_one(ptr, tmp_path, bad, retries=2, sleep=lambda s: None)
    assert out.startswith("failed") and not (tmp_path / "x.csv").exists()
