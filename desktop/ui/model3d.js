// The Aerox 9 scan (assets/Aerox9.mesh, made by tools/make_mesh.py) as a black body,
// with the 12 side keys drawn as clean numbered caps where the scan measured them.
// A highlighted key gets an accent-coloured ring around its cap. Same scene as the
// Mac app's SceneKit view.

import * as THREE from "./vendor/three.module.js";

const CAP_DEPTH = 1.6;
const CAP_BEVEL = 0.3;

export class MouseModel3D {
  constructor(canvas, accent) {
    this.canvas = canvas;
    this.accent = new THREE.Color(accent);
    this.caps = {};   // "S1"… → face material
    this.rings = {};  // "S1"… → ring material
    this.renderer = new THREE.WebGLRenderer({ canvas, antialias: true, alpha: true });
    this.renderer.setPixelRatio(window.devicePixelRatio);
    this.renderer.outputColorSpace = THREE.SRGBColorSpace;
    this.scene = new THREE.Scene();

    // Soft studio light: a bright-above, dark-below environment for reflections, a key
    // light from the camera side and a rim light behind to outline the shell.
    const sky = document.createElement("canvas");
    sky.width = 64; sky.height = 32;
    const g = sky.getContext("2d");
    const grad = g.createLinearGradient(0, 0, 0, 32);
    grad.addColorStop(0, "#f2f2f2"); grad.addColorStop(1, "#0a0a0a");
    g.fillStyle = grad; g.fillRect(0, 0, 64, 32);
    const skyTexture = new THREE.CanvasTexture(sky);
    skyTexture.mapping = THREE.EquirectangularReflectionMapping;
    skyTexture.colorSpace = THREE.SRGBColorSpace;
    const pmrem = new THREE.PMREMGenerator(this.renderer);
    this.scene.environment = pmrem.fromEquirectangular(skyTexture).texture;
    this.scene.add(new THREE.AmbientLight(0xffffff, 0.35));
    for (const [pos, intensity] of [[[-1.6, 2, -1], 2.4], [[1, 1.2, 1.6], 2.0]]) {
      const light = new THREE.DirectionalLight(0xffffff, intensity);
      light.position.set(...pos);
      this.scene.add(light);
    }

    // Fixed view of the whole mouse from its button side, slightly from above.
    this.camera = new THREE.PerspectiveCamera(13, 1, 0.01, 100);
    this.camera.position.set(-2.75, 0.75, -0.25);
    this.camera.lookAt(0, 0.19, 0);

    // Mesh space → scene space: mm → 1/100, z up → y up, front stays at -z, grid on -x.
    this.mouse = new THREE.Group();
    this.mouse.matrixAutoUpdate = false;
    this.mouse.matrix.set(-0.01, 0, 0, 0, 0, 0, 0.01, 0, 0, 0.01, 0, 0, 0, 0, 0, 1);
    this.scene.add(this.mouse);

    this.state = { selected: null, hovered: null, flashing: new Set() };
    this.current = {};  // animated ring opacity / tint per key
    new ResizeObserver(() => this.resize()).observe(canvas);
    this.resize();
  }

  async load(url) {
    const data = await (await fetch(url)).arrayBuffer();
    this.build(data);
    this.render();
  }

  /** Reads the format written by tools/make_mesh.py. */
  build(data) {
    const magic = new TextDecoder().decode(new Uint8Array(data, 0, 4));
    if (magic !== "OSM2") return;
    let offset = 4;
    const view = new DataView(data);
    const u32 = (n) => { const a = new Uint32Array(data.slice(offset, offset + 4 * n)); offset += 4 * n; return a; };
    const f32 = (n) => { const a = new Float32Array(data.slice(offset, offset + 4 * n)); offset += 4 * n; return a; };
    const [vertexCount, triangleCount] = [view.getUint32(4, true), view.getUint32(8, true)];
    offset = 12;
    const positions = f32(vertexCount * 3);
    const normals = f32(vertexCount * 3);
    const indices = u32(triangleCount * 3);

    const body = new THREE.BufferGeometry();
    body.setAttribute("position", new THREE.BufferAttribute(positions, 3));
    body.setAttribute("normal", new THREE.BufferAttribute(normals, 3));
    body.setIndex(new THREE.BufferAttribute(indices, 1));
    // Matte black with a faint sheen; double-sided as the scan has a few flipped faces.
    const shell = new THREE.MeshPhongMaterial({
      color: new THREE.Color().setRGB(0.06, 0.06, 0.06, THREE.SRGBColorSpace),
      specular: new THREE.Color().setRGB(0.22, 0.22, 0.22, THREE.SRGBColorSpace),
      shininess: 18,
      side: THREE.DoubleSide,
    });
    this.mouse.add(new THREE.Mesh(body, shell));

    for (let number = 1; number <= 12; number++) {
      const f = f32(15);
      const frame = new THREE.Group();
      frame.matrixAutoUpdate = false;
      frame.matrix.makeBasis(
        new THREE.Vector3(f[3], f[4], f[5]),
        new THREE.Vector3(f[6], f[7], f[8]),
        new THREE.Vector3(f[9], f[10], f[11]));
      frame.matrix.setPosition(f[0], f[1], f[2]);
      this.mouse.add(frame);
      const cap = new KeyCap(number, f[12], f[13], f[14]);
      const { mesh, face } = cap.capMesh();
      const { mesh: ring, material } = cap.ringMesh(this.accent);
      frame.add(mesh, ring);
      this.caps[`S${number}`] = face;
      this.rings[`S${number}`] = material;
      this.current[`S${number}`] = { ring: 0, tint: 0 };
    }
  }

  resize() {
    const { clientWidth: w, clientHeight: h } = this.canvas;
    if (!w || !h) return;
    this.renderer.setSize(w, h, false);
    this.camera.aspect = w / h;
    this.camera.updateProjectionMatrix();
    this.render();
  }

  setAccent(colour) {
    this.accent.set(colour);
    for (const m of Object.values(this.rings)) m.color.copy(this.accent);
    this.highlight(this.state, false);
  }

  /** Pressed > selected > hovered, each clearly different: a press and a selection both
   *  tint the key face (a press more strongly); hover is only a faint outline. */
  highlight(state, animated = true) {
    this.state = state;
    const target = {};
    for (const id of Object.keys(this.rings)) {
      const pressed = state.flashing.has(id);
      target[id] = {
        ring: pressed || id === state.selected ? 1 : id === state.hovered ? 0.4 : 0,
        tint: pressed ? 0.6 : id === state.selected ? 0.3 : 0,
      };
    }
    const start = performance.now(), from = structuredClone(this.current);
    const duration = animated ? 120 : 0;
    const step = (now) => {
      const t = duration ? Math.min(1, (now - start) / duration) : 1;
      for (const id of Object.keys(target)) {
        const c = this.current[id];
        c.ring = from[id].ring + (target[id].ring - from[id].ring) * t;
        c.tint = from[id].tint + (target[id].tint - from[id].tint) * t;
        this.rings[id].opacity = c.ring;
        this.rings[id].visible = c.ring > 0.001;
        this.caps[id].emissive.copy(this.accent).multiplyScalar(c.tint);
      }
      this.render();
      if (t < 1) this.frame = requestAnimationFrame(step);
    };
    cancelAnimationFrame(this.frame);
    this.frame = requestAnimationFrame(step);
  }

  render() {
    this.renderer.render(this.scene, this.camera);
  }
}

/** One side key drawn as a clean cap: a slanted, rounded parallelogram with its number
 *  printed on top, like the real keys. Its local frame is x along the key, y up it, z out
 *  of the mouse, with the origin at the centre of the top face. Units are mm. */
class KeyCap {
  constructor(number, width, height, lean) {
    Object.assign(this, { number, width, height, lean });
  }

  /** The cap's corners grown by `margin`, going round from bottom-left. */
  corners(margin) {
    const w = this.width / 2 + margin, h = this.height / 2 + margin;
    return [[-w, -h], [w, -h], [w, h], [-w, h]].map(([x, y]) => new THREE.Vector2(x + this.lean * y, y));
  }

  roundedPath(margin, radius, path = new THREE.Shape()) {
    const c = this.corners(margin);
    for (let i = 0; i < 4; i++) {
      const prev = c[(i + 3) % 4], corner = c[i], next = c[(i + 1) % 4];
      const a = corner.clone().add(prev.clone().sub(corner).setLength(radius));
      const b = corner.clone().add(next.clone().sub(corner).setLength(radius));
      if (i === 0) path.moveTo(a.x, a.y); else path.lineTo(a.x, a.y);
      path.quadraticCurveTo(corner.x, corner.y, b.x, b.y);
    }
    path.closePath();
    return path;
  }

  capMesh() {
    const shape = this.roundedPath(-CAP_BEVEL, 0.7);
    const geometry = new THREE.ExtrudeGeometry(shape, {
      depth: CAP_DEPTH - 2 * CAP_BEVEL, bevelEnabled: true, bevelThickness: CAP_BEVEL,
      bevelSize: CAP_BEVEL, bevelSegments: 3, curveSegments: 6,
    });
    // The cap faces get UVs in mm; map the label over the cap's bounding box.
    const box = new THREE.Box2().setFromPoints(this.corners(0));
    const size = box.getSize(new THREE.Vector2());
    const label = this.labelTexture(size);
    label.repeat.set(1 / size.x, 1 / size.y);
    label.offset.set(-box.min.x / size.x, -box.min.y / size.y);
    // The real keys have a fine metallic sparkle.
    const face = new THREE.MeshStandardMaterial({ map: label, roughness: 0.42, metalness: 0.35, emissive: 0x000000 });
    const sides = new THREE.MeshStandardMaterial({
      color: new THREE.Color().setRGB(0.26, 0.26, 0.26, THREE.SRGBColorSpace), roughness: 0.5, metalness: 0.3 });
    const mesh = new THREE.Mesh(geometry, [face, sides]);
    mesh.position.z = 0.15 - CAP_DEPTH + CAP_BEVEL;  // top face just proud of the scan
    return { mesh, face };
  }

  /** A thin ring just outside the cap, level with its top face. */
  ringMesh(accent) {
    const outer = this.roundedPath(0.75, 1.4);
    outer.holes.push(this.roundedPath(0.2, 1.0, new THREE.Path()));
    const geometry = new THREE.ExtrudeGeometry(outer, { depth: 0.3, bevelEnabled: false, curveSegments: 6 });
    const material = new THREE.MeshBasicMaterial({
      color: accent.clone(), transparent: true, opacity: 0, side: THREE.DoubleSide, depthWrite: false });
    material.visible = false;
    const mesh = new THREE.Mesh(geometry, material);
    mesh.position.z = -0.05;
    mesh.renderOrder = 1;
    return { mesh, material };
  }

  /** The cap's top-face texture: grey with the key's number. */
  labelTexture(size) {
    const scale = 40;  // pixels per mm
    const canvas = document.createElement("canvas");
    canvas.width = Math.round(size.x * scale);
    canvas.height = Math.round(size.y * scale);
    const g = canvas.getContext("2d");
    g.fillStyle = "rgb(143,143,143)";
    g.fillRect(0, 0, canvas.width, canvas.height);
    g.fillStyle = "rgb(204,219,235)";
    g.font = `500 ${this.height * 0.48 * scale}px system-ui, "Segoe UI", sans-serif`;
    g.textAlign = "center";
    g.textBaseline = "middle";
    g.fillText(String(this.number), canvas.width / 2, canvas.height / 2);
    const texture = new THREE.CanvasTexture(canvas);
    texture.colorSpace = THREE.SRGBColorSpace;
    texture.anisotropy = 4;
    return texture;
  }
}
