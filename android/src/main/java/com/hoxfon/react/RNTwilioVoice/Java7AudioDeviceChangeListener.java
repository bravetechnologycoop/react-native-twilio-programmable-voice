package com.hoxfon.react.RNTwilioVoice;

import com.twilio.audioswitch.AudioDevice;

import java.util.List;

public interface Java7AudioDeviceChangeListener 
{
    void onAudioDevicesChanged(List<AudioDevice> audioDevices, AudioDevice audioDevice);
}
