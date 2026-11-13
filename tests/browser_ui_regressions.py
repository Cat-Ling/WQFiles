#!/usr/bin/env python3
"""Static regression checks for UIKit backup/restore and sharing paths."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
main = (ROOT / "main.m").read_text()
apps = (ROOT / "WQApps.m").read_text()
sharing = (ROOT / "WQSharing.m").read_text()
ui = (ROOT / "WQUI.m").read_text()
header = (ROOT / "WQSharing.h").read_text()


def require(text: str, needle: str, label: str) -> None:
    if needle not in text:
        raise AssertionError(f"missing {label}: {needle}")


def forbid(text: str, needle: str, label: str) -> None:
    if needle in text:
        raise AssertionError(f"stale {label}: {needle}")


# Start screen & health checks
health_present = main.split("- (void)presentPendingHealthFailure", 1)[1].split("// Each set of warnings", 1)[0]
require(health_present, "if (![self healthFailureCanPresent])", "startup failure waits for an idle start screen")
forbid(health_present, "while (host.presentedViewController)", "startup failure presented over open actions")
require(main, "@\"App Backups\"", "App Backups shortcut")
require(main, "[WQAppBackupsViewController new]", "App Backups destination")
require(main, "wq_app_backup_mode()", "Backup Mode setting on start screen")
require(main, "pickBackupModeFrom:", "Backup Mode picker sheet")
forbid(main, "WQDirViewController", "removed directory browser")
forbid(main, "WQPlistEditorViewController", "removed plist editor")
forbid(main, "WQCacheViewController", "removed cache cleaner")
forbid(main, "WQRecentlyDeletedViewController", "removed trash view")

# Apps, IPA packaging, and App Backups screen
require(apps, "wq_make_app_ipa", "IPA packaging helper")
require(apps, "io.skipUnreadable = NO;", "strict unreadable refusal during IPA zip")
require(apps, "@\"Payload\" stringByAppendingPathComponent:bundlePath.lastPathComponent", "Payload bundle layout")
require(apps, "@[@\"iTunesMetadata.plist\", @\"iTunesArtwork\", @\"iTunesArtwork@2x\"]", "iTunes metadata packaging")
require(apps, "@\"SC_Info\"", "FairPlay SC_Info check")
require(apps, "@\"_CodeSignature\"", "CodeSignature check")
require(apps, "@[@\"META-INF\", @\"StoreKit\"]", "META-INF and StoreKit packaging")
require(apps, "wq_app_backup_mode()", "app action uses configured Backup Mode")
require(apps, "backUpWithSettings:", "mode-aware backup flow")
require(apps, "pickIPAToShare:", "multi-IPA share sheet")
require(apps, "@implementation WQAppBackupsViewController", "App Backups list controller")
require(apps, "wq_delete_backup", "explicit backup deletion")
require(apps, "wq_share(self, path, source);", "IPA sharing")
forbid(apps, "Open Data Folder", "removed data folder browser action")
forbid(apps, "Open App Bundle", "removed app bundle browser action")
forbid(apps, "WQDir.h", "removed directory header import")

# Sharing and alert host guards
require(header, "void wq_share_cancel(UIViewController *host);", "share cancellation API")
require(sharing, "__weak UIViewController *weakHost", "weak sharing host")
require(sharing, "preparation.cancelled", "abandoned folder preparation")
require(sharing, "wq_remove_export(outDir)", "abandoned export cleanup")
require(sharing, "Only regular files can be shared.", "special-file share refusal")
require(ui, "host.presentedViewController && !host.presentedViewController.isBeingDismissed", "validated alert host")
require(sharing, "Share in progress", "share in-flight guard")
require(sharing, "wq_clear_in_flight", "share in-flight cleanup")
require(sharing, "wq_alert_action(@\"Cancel\"", "folder share cancel action")
clear_preparation = sharing.split("static void wq_clear_preparation", 1)[1].split("static BOOL wq_present_share", 1)[0]
require(clear_preparation, "if (!host) return;", "nil weak host association guard")

print("browser UI regression checks: PASS")
