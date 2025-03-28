"""
Patched voice.py with disabled imports to avoid dependency issues.
This is automatically loaded when AIDER_VOICE_DISABLED=True
"""

import os
import warnings

from prompt_toolkit.shortcuts import prompt
from .dump import dump  # noqa: F401

class SoundDeviceError(Exception):
    pass

class Voice:
    """Disabled Voice class that raises an error when used"""
    
    def __init__(self, audio_format="wav", device_name=None):
        raise SoundDeviceError("Voice support is disabled")
        
    def record_and_transcribe(self, history=None, language=None):
        raise SoundDeviceError("Voice support is disabled")

# Define these to avoid import errors elsewhere
AudioSegment = None
CouldntDecodeError = None
CouldntEncodeError = None 