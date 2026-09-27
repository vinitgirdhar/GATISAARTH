// Local street geometry and routing for the website experience only.
export const places = [
  {
    name: "Your location",
    detail: "Near CSMT, Mumbai",
    point: [72.8347, 18.9401],
  },
  {
    name: "Gateway of India",
    detail: "Apollo Bandar, Colaba",
    point: [72.8346, 18.9221],
  },
  {
    name: "Marine Drive",
    detail: "Queen’s Necklace, Mumbai",
    point: [72.8239, 18.9347],
  },
  {
    name: "Churchgate Station",
    detail: "Churchgate, Mumbai",
    point: [72.8265, 18.9322],
  },
  {
    name: "Chhatrapati Shivaji Maharaj Terminus",
    detail: "CSMT, Fort, Mumbai",
    point: [72.8353, 18.9398],
  },
  {
    name: "Flora Fountain",
    detail: "Hutatma Chowk, Fort",
    point: [72.8314, 18.9325],
  },
  {
    name: "Kala Ghoda",
    detail: "Art district, Mumbai",
    point: [72.8324, 18.9283],
  },
];
export const project = ([lon, lat]) => [
  (lon - 72.817) * 44000,
  (18.948 - lat) * 46500,
];
export const unproject = ([x, y]) => [x / 44000 + 72.817, 18.948 - y / 46500];
const distance = (a, b) => Math.hypot(a[0] - b[0], a[1] - b[1]);
const escape = (text) =>
  String(text).replace(
    /[&<>"']/g,
    (c) =>
      ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[
        c
      ],
  );
const pointsPath = (points) =>
  points
    .map(
      (p, i) =>
        `${i ? "L" : "M"}${project(p)
          .map((n) => n.toFixed(1))
          .join(",")}`,
    )
    .join("");
export class CityMap {
  constructor(data) {
    this.nodes = new Map();
    const polygons = (items, cls) =>
      `<path class="${cls}" fill-rule="evenodd" d="${items.map((rings) => rings.map((r) => pointsPath(r) + "Z").join("")).join("")}"/>`;
    const paths = { major: [], minor: [] },
      labels = [],
      named = new Set();
    this.labels = [];
    for (const road of data.roads) {
      const major = ["major_road", "highway"].includes(road.kind);
      if (road.kind === "rail") continue;
      paths[major ? "major" : "minor"].push(pointsPath(road.points));
      if (
        road.name &&
        !named.has(road.name) &&
        road.points.length > 3 &&
        major
      ) {
        named.add(road.name);
        const p = project(road.points[Math.floor(road.points.length / 2)]);
        this.labels.push({ point: p, name: road.name });
        labels.push(
          `<text x="${p[0]}" y="${p[1]}" class="street-label">${escape(road.name)}</text>`,
        );
      }
      if (["path", "ferry", "aeroway"].includes(road.kind)) continue;
      for (let i = 0; i < road.points.length; i++) {
        const p = road.points[i],
          key = p.join(",");
        if (!this.nodes.has(key))
          this.nodes.set(key, { key, p, xy: project(p), links: [] });
        if (i) {
          const previous = this.nodes.get(road.points[i - 1].join(",")),
            current = this.nodes.get(key);
          const weight = distance(previous.xy, current.xy);
          previous.links.push({ node: current, weight, name: road.name });
          current.links.push({ node: previous, weight, name: road.name });
        }
      }
    }
    this.svg = `${polygons(data.water, "water")}${polygons(data.parks, "park")}${polygons(data.buildings, "building")}${Object.entries(
      paths,
    )
      .map(
        ([kind, lines]) =>
          `<path class="street ${kind}" d="${lines.join("")}"/>`,
      )
      .join("")}${labels.join("")}`;
    // Favor the main connected street network over isolated paths or tile fragments.
    let largest = [];
    const visited = new Set();
    for (const node of this.nodes.values()) {
      if (visited.has(node.key)) continue;
      const component = [node];
      visited.add(node.key);
      for (let i = 0; i < component.length; i++)
        for (const edge of component[i].links) {
          if (!visited.has(edge.node.key)) {
            visited.add(edge.node.key);
            component.push(edge.node);
          }
        }
      if (component.length > largest.length) largest = component;
    }
    this.connected = largest;
  }
  nearest(point) {
    const xy = project(point);
    return this.connected.reduce((best, node) =>
      distance(xy, node.xy) < distance(xy, best.xy) ? node : best,
    );
  }
  route(from, to) {
    // ponytail: small, local sample graph; use a routing engine for turn restrictions or city-wide coverage.
    const start = this.nearest(from.point),
      end = this.nearest(to.point);
    const costs = new Map([[start.key, 0]]),
      prev = new Map(),
      queue = [{ node: start, cost: 0 }];
    while (queue.length) {
      queue.sort((a, b) => b.cost - a.cost);
      const { node, cost } = queue.pop();
      if (node === end) break;
      if (cost > costs.get(node.key)) continue;
      for (const edge of node.links) {
        const next = cost + edge.weight;
        if (next < (costs.get(edge.node.key) ?? Infinity)) {
          costs.set(edge.node.key, next);
          prev.set(edge.node.key, { node, name: edge.name });
          queue.push({ node: edge.node, cost: next });
        }
      }
    }
    if (!costs.has(end.key))
      throw new Error("Choose another destination in central Mumbai.");
    const points = [end.xy],
      names = [];
    let at = end;
    while (at !== start) {
      const entry = prev.get(at.key);
      names.unshift(entry.name);
      at = entry.node;
      points.unshift(at.xy);
    }
    if (points.length < 2)
      throw new Error("Choose a destination farther from your starting point.");
    const lengths = [0];
    for (let i = 1; i < points.length; i++)
      lengths.push(lengths[i - 1] + distance(points[i - 1], points[i]));
    return {
      points,
      names,
      lengths,
      total: lengths.at(-1),
      km: (lengths.at(-1) * 2.39) / 1000,
      path: points.map((p, i) => `${i ? "L" : "M"}${p.join(",")}`).join(""),
    };
  }
}
export function along(route, progress) {
  const target = Math.min(1, Math.max(0, progress)) * route.total;
  let i = route.lengths.findIndex((length) => length >= target);
  i = Math.max(1, i);
  const a = route.points[i - 1],
    b = route.points[i];
  const t =
    (target - route.lengths[i - 1]) /
    (route.lengths[i] - route.lengths[i - 1] || 1);
  const name =
    route.names[i - 1] || route.names.slice(i).find(Boolean) || "Mumbai road";
  let next = i;
  while (
    next < route.names.length &&
    (!route.names[next] || route.names[next] === name)
  )
    next++;
  return {
    point: [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t],
    name,
    remainingM:
      (route.lengths[Math.min(next + 1, route.lengths.length - 1)] - target) *
      2.39,
    heading: (Math.atan2(b[0] - a[0], a[1] - b[1]) * 180) / Math.PI,
  };
}
