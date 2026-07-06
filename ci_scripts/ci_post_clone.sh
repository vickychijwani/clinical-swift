#!/bin/sh
set -e

# Avoid macro trust errors like "Macro abc from package xyz must be enabled before it can be used"
defaults write com.apple.dt.Xcode IDESkipMacroFingerprintValidation -bool YES

