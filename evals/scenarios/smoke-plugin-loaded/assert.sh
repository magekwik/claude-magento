#!/usr/bin/env bash
# Passes once at least one magento:* skill is visible to Claude.
grep -Eq 'magento:[a-z-]+' "$TRANSCRIPT"
