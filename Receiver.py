import serial
import os
import time
PORT = "COM3"       # Change this to your STM32 COM port
BAUD = 115200
TOTAL_BYTES = 2048
output_file = os.path.join(
    os.path.expanduser("~"),
    "Downloads",
    "audio_capture.dat"
)
try:
    with serial.Serial(PORT, BAUD, timeout=2) as ser:
        time.sleep(2)
        ser.reset_input_buffer()

        print("Receiver ready.")
        print("Reset the STM32 board now.")

        received = 0

        with open(output_file, "wb") as f:
            while received < TOTAL_BYTES:
                chunk = ser.read(min(4096, TOTAL_BYTES - received))

                if chunk:
                    f.write(chunk)
                    received += len(chunk)
                    print(
                        f"\rReceived {received}/{TOTAL_BYTES} bytes",
                        end="",
                        flush=True
                    )

        print("\nSaved:", output_file)
except Exception as e:
    print("\nERROR:", e)