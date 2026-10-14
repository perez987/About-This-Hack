//
//  Tooltips.swift
//  About This Hack
//

import Foundation

/// Tooltips class with lazy computed properties to avoid expensive operations at module load time
/// All properties are computed on-demand and thread-safe
final class Tooltips: @unchecked Sendable {
    static let shared = Tooltips()
    private init() {}

    private var _macModeltoolTip: String?
    private let macModelTooltipLock = NSLock()

    var osVersiontoolTip: String {
        HCVersion.shared.getOSBuildInfo()
    }

    var systemVersiontoolTip: String {
        osVersiontoolTip
    }

    var macModeltoolTip: String {
        macModelTooltipLock.lock()
        defer { macModelTooltipLock.unlock() }

        if let cached = _macModeltoolTip {
            return cached
        }

        let pciData = run("system_profiler SPPCIDataType 2>/dev/null | grep \":$\" | sed 's/://g'")
        let computed = HCMacModel.shared.macName + " - " + HCMacModel.shared.getModelIdentifier() + "\n" + pciData
        _macModeltoolTip = computed
        return computed
    }

    var cputoolTip: String {
        HCCPU.shared.getCPU() + "\n" + HCCPU.shared.getCPUInfo()
    }

    var ramtoolTip: String {
        HardwareCollector.shared.getCachedFileContent(InitGlobVar.sysmemFilePath) ?? ""
    }

    var startupDisktoolTip: String {
        HCStartupDisk.shared.getStartupDiskInfo()
    }

    var displaytoolTip: String {
        HCDisplay.shared.getDispInfo()
    }

    var graphicstoolTip: String {
        HCGPU.shared.getGPUInfo()
    }

    var serialToggletoolTip: String {
        HCSerialNumber.shared.getHardwareInfo()
    }

    var startupDiskImagetoolTip: String {
        HardwareCollector.shared.getCachedFileContent(InitGlobVar.bootvollistFilePath) ?? ""
    }

    var storageValuetoolTip: String {
        startupDisktoolTip
    }

    var blVersiontoolTip: String {
        String(format: NSLocalizedString("tooltip.bootloader", comment: "Bootloader tooltip format"),
               HCBootloader.shared.getBootloader(),
               HCBootloader.shared.getBootargs())
    }

    var btSysInfotoolTip: String {
        NSLocalizedString("tooltip.sysinfo", comment: "System Info button tooltip")
    }

    var btSoftUpdtoolTip: String {
        NSLocalizedString("tooltip.softupd", comment: "Software Update button tooltip")
    }
}
