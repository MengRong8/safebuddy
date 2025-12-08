import serial
import time

# --- CONFIGURATION ---
# CHANGE THIS to the Bluetooth COM port 
SERIAL_PORT = 'COM8' 
BAUD_RATE = 9600
# ---------------------

print(f"Connecting to {SERIAL_PORT} (Bluetooth)...")

try:
    # Connect to the "Virtual" Cable
    ser = serial.Serial(SERIAL_PORT, BAUD_RATE)
    print("Connected! Waiting for button press...")

    while True:
        if ser.in_waiting > 0:
            line = ser.readline().decode('utf-8').strip()
            print(f"Received: {line}")
            
            if line == "pressed":
                print(">>> BLUETOOTH SUCCESS!")

except serial.SerialException:
    print(f"Could not open {SERIAL_PORT}.")
