# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/), and this project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]
### Added
- Support for new features to enhance bootable USB creation.
- Detailed logging to track the process.
- New command-line options for customization.

### Changed
- Improved error handling for unsupported USB devices.
- Updated default filesystem to `NTFS` for larger drives.

### Fixed
- Resolved issue with incorrect partition size allocation.
- Fixed bugs related to drive detection on Windows 11.

## [1.1.0] - 2024-12-30
### Added
- Added progress indicators during formatting and copying operations.
- Support for creating bootable USBs for Linux distributions.

### Changed
- Enhanced script readability and modularized key functions.
- Switched default format from `FAT32` to `exFAT` for better compatibility.

### Fixed
- Fixed issues with drive letter assignment in certain scenarios.

## [1.0.0] - 2024-12-15
### Added
- Initial release of the Create-BootableUSB script.
- Support for creating bootable USB drives for Windows installations.
- Automatically formats the drive and sets it as active.
