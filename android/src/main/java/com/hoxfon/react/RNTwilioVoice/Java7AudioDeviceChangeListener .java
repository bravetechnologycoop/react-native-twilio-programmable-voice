import com.twilio.audioswitch.AudioDevice;

public interface Java7AudioDeviceChangeListener 
{
    public void onAudioDevicesChanged(List<AudioDevice> audioDevices, AudioDevice audioDevice);
}
