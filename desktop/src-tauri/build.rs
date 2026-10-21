fn main() {
    // The 3D mouse lives once in model/; copy it into the page's assets before Tauri
    // embeds them.
    let mesh = "../../model/Aerox9.mesh";
    println!("cargo:rerun-if-changed={mesh}");
    std::fs::create_dir_all("../ui/assets").expect("create ui/assets");
    std::fs::copy(mesh, "../ui/assets/Aerox9.mesh").expect("copy model/Aerox9.mesh");
    tauri_build::build()
}
