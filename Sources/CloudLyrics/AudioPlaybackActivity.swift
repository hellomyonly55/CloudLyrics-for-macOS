import AppKit
import CoreAudio
import Foundation

protocol AudioPlaybackActivityProviding {
    func isRunningOutput(bundleIdentifier: String) -> Bool?
}

struct CoreAudioPlaybackActivity: AudioPlaybackActivityProviding {
    func isRunningOutput(bundleIdentifier: String) -> Bool? {
        let applications = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
        guard !applications.isEmpty else { return false }
        var receivedKnownState = false
        for application in applications {
            guard let isRunning = isRunningOutput(processIdentifier: application.processIdentifier) else { continue }
            receivedKnownState = true
            if isRunning { return true }
        }
        return receivedKnownState ? false : nil
    }

    private func isRunningOutput(processIdentifier: pid_t) -> Bool? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var processIdentifier = processIdentifier
        var processObject: AudioObjectID = 0
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let translationStatus = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            UInt32(MemoryLayout<pid_t>.size),
            &processIdentifier,
            &size,
            &processObject
        )
        guard translationStatus == noErr, processObject != 0 else { return nil }

        address.mSelector = kAudioProcessPropertyIsRunningOutput
        var value: UInt32 = 0
        size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(processObject, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value != 0
    }
}
