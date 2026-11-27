// Written by `coolhead ranking --write`; checked by `coolhead selftest` (see Ranking.swift). One line per sample
// card: sample · card · state · → recommended option · every option in order. Rewrite it in the pull request
// that changes a line, so the change shows in the diff.
enum GoldenRanking {
    static let text = #"""
    job-with-progress · job · working · → none · stop, cooler
    job-stalled · job · stalled · → stop · stop, share
    job-waiting · job · waiting · → none · stop
    job-no-signs · job · unknown · → cooler · cooler, stop, lookup, share
    spotlight-normal · catalogue · working · → none · no options
    spotlight-long · catalogue · unknown · → lookup · lookup, share
    kernel-task-long · catalogue · unknown · → advice · advice, lookup, share
    browser-tab · web-page · unknown · → find · find, quit, lookup
    docker-vm · catalogue · working · → none · quit
    intel-app-26 · job · unknown · → cooler · cooler, lookup, intel, share
    intel-app-27 · job · unknown · → cooler · cooler, intel, lookup, share
    app-set-to-rosetta · job · unknown · → cooler · cooler, native, lookup, share
    windowserver-old-electron · catalogue · working · → electron · electron
    spotlight-low-priority · catalogue · working · → none · no options
    spotlight-after-update · catalogue · working · → none · no options
    stuck-macos-service · background-stuck · unknown · → restart · restart, share
    stuck-after-restart · background-stuck · unknown · → update · update, feedback, share
    browser-policy · - · unknown · → policy-page · policy-page, profiles
    browser-scripted · - · unknown · → reveal-extension · reveal-extension, quit
    pause-offered · job · unknown · → pausejob · pausejob, stop, cooler, lookup, share
    pause-held-sound · job · unknown · → cooler · cooler, stop, lookup, share
    pause-held-download · job · unknown · → cooler · cooler, stop, lookup, share
    catalogue-docker-vm · catalogue · working · → none · quit
    catalogue-sound · catalogue · working · → none · no options
    catalogue-sound-long · catalogue · unknown · → advice · advice, lookup, share
    catalogue-contacts-sync · catalogue · working · → none · no options
    catalogue-contacts-sync-long · catalogue · unknown · → advice · advice, lookup, share
    catalogue-messages-sync · catalogue · working · → none · no options
    catalogue-messages-sync-long · catalogue · unknown · → advice · advice, lookup, share
    catalogue-aerial-downloads · catalogue · working · → none · no options
    catalogue-aerial-downloads-long · catalogue · unknown · → advice · advice, lookup, share
    catalogue-displaylink · catalogue · working · → none · quit
    catalogue-displaylink-long · catalogue · unknown · → quit · quit, advice, lookup, share
    catalogue-local-ai-model · catalogue · working · → none · no options
    catalogue-local-ai-model-long · catalogue · unknown · → advice · advice, lookup, share
    memory-chrome-companion · - · unknown · → sleep · sleep, extensions, groups, duplicates, restart, quit, saver, tabmemory
    memory-chrome-companion-none-to-sleep · - · unknown · → none · extensions, groups, duplicates, restart, quit, saver, tabmemory, sleep
    memory-chrome-get-companion · - · unknown · → tabs · tabs, restart, quit, saver, tabmemory, extensions, groups, companion
    memory-chrome-second-companion · - · unknown · → sleep · sleep, restart, quit2
    memory-chrome-saver-max · - · unknown · → tabs · tabs, saver-max, restart, quit, tabmemory
    memory-chrome-hidden-tabs · - · unknown · → tabs · tabs, restart, quit, saver, tabmemory, extensions, groups
    memory-chrome-grown · - · unknown · → restart · restart, tabs, quit, saver, tabmemory
    cap-offered · job · unknown · → cpucap · cpucap, lookup, share
    cap-half · - · unknown · → cpucap · cpucap
    crash-loop · - · unknown · → lookup · lookup, console
    disguise-macos-name · disguise · unknown · → remove · remove, share
    disguise-apple-label · disguise · unknown · → remove · remove, share
    disguise-protection-off · disguise · unknown · → protect · protect, reinstall, share
    memory-leaking-app · - · unknown · → reopen · reopen, quit2
    memory-ollama-model · - · unknown · → unload · unload, quit2, lookup
    memory-low-disk-xcode · - · unknown · → builddata · builddata, quit, disk
    power-low-adapter · - · quiet · → battery-settings · battery-settings
    power-held-awake · - · quiet · → none · quit
    power-held-awake-sound · - · working · → none · quit
    power-night-wakes · - · quiet · → battery-options · battery-options
    power-night-upkeep · - · quiet · → battery-options · battery-options
    memory-chrome-warning-unmoved · - · unknown · → tabs · tabs, restart, quit, saver, tabmemory
    memory-chrome-week · - · unknown · → tabs · tabs, restart, quit, saver, tabmemory
    virtual-machine · job · unknown · → lookup · lookup, stop, cooler, share
    web-page-in-app · web-page-in-app · unknown · → quit · quit, lookup
    macos-service-for-app · served · unknown · → quit · quit, lookup
    macos-unknown-low-priority · unknown-service · working · → none · lookup
    macos-unknown-normal-priority · unknown-service · unknown · → none · lookup
    background-helper · job · unknown · → cooler · cooler, agent, lookup, share
    time-machine-build · catalogue · working · → backup · backup
    memory-chrome · - · unknown · → tabs · tabs, restart, quit, saver, tabmemory
    memory-safari · - · unknown · → tabs · tabs, quit
    memory-edge · - · unknown · → tabs · tabs, restart, quit, saver
    memory-sync-app · - · unknown · → quit · quit, restart, quit2, pause
    memory-app-and-program-alike · - · unknown · → none · quit
    memory-program-first · - · unknown · → none · quit2, lookup
    memory-low-disk · - · unknown · → quit · quit, disk
    memory-heavy-swap · - · unknown · → none · quit
    memory-docker · - · unknown · → none · quit
    memory-job · - · unknown · → none · no options
    hang-paused-in-terminal · - · waiting · → fg · fg, stop
    hang-paused-by-something-else · - · unknown · → resume · resume, stop, lookup, share
    hang-waiting-on-a-drive · - · unknown · → drive · drive, restart, lookup, share
    hang-started-a-program-of-its-own-name · - · unknown · → resume · resume, stop, lookup, share
    hang-not-responding-new · - · unknown · → none · forcequit, lookup, share
    hang-not-responding-settled · - · unknown · → forcequit · forcequit, lookup, share
    chrome-tab · chromium-browser · unknown · → cooler · cooler, find, closetab, quit, page
    chrome-tab-in-front-warm · chromium-browser · unknown · → page · page, find, closetab, quit, cooler
    chrome-extension · chromium-browser · unknown · → cooler · cooler, page, find, stopext, quit
    chrome-graphics · chromium-browser · unknown · → page · page, find, quit
    safari-tab · web-page · unknown · → find · find, quit, lookup
    web-page-drawing · web-page · unknown · → find · find, quit, lookup
    sync-app · sync-app · working · → none · quit, cooler, pause
    sync-app-warm-fed-by-a-build · sync-app · working · → cooler · cooler, movebuild, quit, pause
    sync-app-fed-in-its-folder · sync-app · working · → cooler · cooler, movebuild, quit, pause
    security-software · security-software · working · → none · lookup
    vpn · security-software · working · → none · disconnect, lookup
    game · game · working · → settings · settings, quit
    app-on-the-graphics-chip · job · unknown · → quit · quit, lookup, share
    job-unknown-warm-on-battery-during-a-game · job · unknown · → pausejob · pausejob, stop, cooler, lookup, share
    job-just-started · job · starting · → none · stop, cooler
    hardware-drive-fault · - · unknown · → backup · backup, diagnostics
    hardware-drive-errors · - · unknown · → backup · backup, diagnostics
    hardware-drive-worn · - · quiet · → none · backup
    hardware-battery-fault · - · unknown · → none · diagnostics, note
    hardware-battery-service · - · unknown · → battery · battery, diagnostics
    hardware-battery-worn · - · quiet · → none · battery
    hardware-battery-warm · - · unknown · → none · no options
    hardware-battery-hot · - · unknown · → none · no options
    hardware-charging-on-hold · - · quiet · → none · full
    hardware-charging-too-warm · - · unknown · → none · no options
    hardware-charging-charger-too-weak · - · quiet · → none · no options
    hardware-charging-unknown · - · quiet · → none · diagnostics
    hardware-crash-this-start · - · unknown · → none · safemode, diagnostics
    hardware-crash-repeated · - · unknown · → none · safemode, diagnostics
    hardware-port-power · - · unknown · → power · power, diagnostics
    hardware-port-drops · - · quiet · → none · diagnostics
    """#
}
