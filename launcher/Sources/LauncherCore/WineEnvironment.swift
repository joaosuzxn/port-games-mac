import Foundation

/// The environment Wine runs with, the same one Sikarugir's `wineskinlauncher` sets up.
///
/// Values come from live captures (2026-10-22 and 2026-10-23, the launcher's own `export` line) of the
/// apps in `build/`, with the app bundle's folders
/// moved to the shared engine: `Contents/SharedSupport/wine` → `<root>/wine`, `Contents/Frameworks` →
/// `<root>/Frameworks`, `Contents/SharedSupport/renderer` → `<root>/renderer` and
/// `Contents/Resources/vulkan` → `<root>/Resources/vulkan`. `WINEDLLPATH` keeps the captured
/// `wine/lib/<arch>` folders even though the DLLs live in `wine/lib/wine/<arch>` (Wine finds those
/// next to itself anyway).
public enum WineEnvironment {
    /// - Parameters:
    ///   - extra: the run's own variables (the Steam bridge, …); they go last and win over the recipe.
    ///   - home: where `~/.cache/dxvk` lives; the user's home by default.
    public static func make(
        engine: Engine, prefix: URL, recipe: Recipe, extra: [String: String] = [:],
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> [String: String] {
        let root = engine.root.standardizedFileURL.path
        let wine = root + "/wine"
        let frameworks = root + "/Frameworks"
        let renderers = root + "/renderer"
        let d3dshared = renderers + "/d3dmetal/external/libd3dshared.dylib"

        var env: [String: String] = [
            "CX_APPLEGPTK_LIBD3DSHARED_PATH": d3dshared,
            "CX_APPLEGPT_LIBD3DSHARED_PATH": d3dshared,
            "CX_FWD_COMPAT_GL_CTX": "1",
            "CX_ROOT": wine,
            "DOTNET_EnableWriteXorExecute": "0",
            "DXMT_ALLOW_CROSS_PROCESS_SWAPCHAIN": "1",
            "DXVK_ASYNC": "1",
            "DXVK_SHADER_CACHE_PATH": home.standardizedFileURL.path + "/.cache/dxvk",
            "DYLD_FALLBACK_LIBRARY_PATH": [
                wine + "/lib", wine + "/lib64", frameworks, frameworks + "/GStreamer.framework/Libraries",
                "/opt/wine/lib", "/usr/lib", "/usr/libexec", "/usr/lib/system",
            ].joined(separator: ":"),
            "GST_PLUGIN_PATH": frameworks + "/GStreamer.framework/Libraries/gstreamer-1.0",
            "MTL_HUD_ENABLED": "0",
            "MVK_CONFIG_FAST_MATH_ENABLED": "0",
            "MVK_CONFIG_RESUME_LOST_DEVICE": "1",
            "PATH": wine + "/bin:/usr/bin:/bin:/usr/sbin:/sbin",
            "QMLSCENE_DEVICE": "softwarecontext",
            "ROSETTA_ADVERTISE_AVX": "1",
            "SDL_JOYSTICK_MFI": "0",
            // The Sikarugir Wine 11 build cannot start any Windows process without it
            // (`run_wineboot failed to start wineboot 1`).
            "SikarugirAppWine11": "1",
            "VK_DRIVER_FILES": engine.vulkanICD.standardizedFileURL.path,
            "WINEBOOT_HIDE_DIALOG": "1",
            "WINEDEBUG": "-all",
            "WINEDLLPATH": [wine + "/lib/x86_64-windows", wine + "/lib/i386-windows", wine + "/lib/x86_64-unix"]
                .joined(separator: ":"),
            "WINEDLLPATH_CNCD": renderers + "/cnc_ddraw/wine",
            "WINEDLLPATH_DXMT": renderers + "/dxmt/wine",
            "WINEDLLPATH_PREPEND": prependFolder(engine: engine, renderer: recipe.renderer),
            "WINEMSYNC": "1",
            "WINEPREFIX": prefix.standardizedFileURL.path,
        ]
        if !recipe.dllOverrides.isEmpty {
            env["WINEDLLOVERRIDES"] = recipe.dllOverrides.sorted { $0.key < $1.key }
                .map { "\($0.key)=\($0.value)" }.joined(separator: ";")
        }
        env.merge(recipe.environment) { _, new in new }
        env.merge(extra) { _, new in new }
        return env
    }

    /// The DLL folder Wine searches before its own. WineD3D keeps Sikarugir's default, DXMT
    /// (Direct3D 10/11 over Metal), which Carros was validated with.
    private static func prependFolder(engine: Engine, renderer: Renderer) -> String {
        switch renderer {
        case .wined3d:
            return engine.root.appendingPathComponent("renderer/dxmt/wine").standardizedFileURL.path
        case .d9vk, .dxvk:
            return engine.rendererDir(renderer)!.standardizedFileURL.path
        case .d3dmetal:
            return engine.rendererDir(renderer)!.appendingPathComponent("wine").standardizedFileURL.path
        }
    }
}
