"""Small, deterministic text selection helpers shared by desktop and Kindle."""
from datetime import date


def daily_index(date_text, count):
    # Stable, dependency-free, identical to the JavaScript FNV-1a implementation.
    value = 2166136261
    for byte in f'kindlexiping261030:v1:{date_text}'.encode('utf-8'):
        value ^= byte
        value = (value * 16777619) & 0xffffffff
    return value % count
