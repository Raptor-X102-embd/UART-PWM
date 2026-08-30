#!/usr/bin/env python3
"""
PWM Control via UART for FPGA (Echo protocol)
Protocol: 4-byte commands:
  - CMD (1 byte): 0x01 = DIVIDER, 0x02 = DUTY
  - DATA (3 bytes): 24-bit value in big-endian order
  - FPGA responds with echo of CMD on successful write.
"""

import serial
import time
import argparse
import sys
import threading
import queue

CMD_DIVIDER = 0x01
CMD_DUTY    = 0x02

class PWMController:
    def __init__(self, port, baudrate=115200, timeout=1.0):
        self.port = port
        self.baudrate = baudrate
        self.timeout = timeout
        self.ser = None
        self.rx_queue = queue.Queue()
        self._reader_thread = None
        self._stop_reader = False

    def open(self):
        try:
            self.ser = serial.Serial(
                port=self.port,
                baudrate=self.baudrate,
                bytesize=serial.EIGHTBITS,
                parity=serial.PARITY_NONE,
                stopbits=serial.STOPBITS_ONE,
                timeout=self.timeout
            )
            self._stop_reader = False
            self._reader_thread = threading.Thread(target=self._reader_loop, daemon=True)
            self._reader_thread.start()
            return True
        except serial.SerialException as e:
            print(f"Error opening port {self.port}: {e}")
            return False

    def close(self):
        self._stop_reader = True
        if self._reader_thread:
            self._reader_thread.join(timeout=0.5)
        if self.ser and self.ser.is_open:
            self.ser.close()

    def _reader_loop(self):
        while not self._stop_reader:
            if self.ser and self.ser.is_open:
                try:
                    if self.ser.in_waiting:
                        byte = self.ser.read(1)
                        if byte:
                            self.rx_queue.put(byte[0])
                except Exception:
                    pass
            time.sleep(0.01)

    def read_byte(self, timeout=0.5):
        try:
            return self.rx_queue.get(timeout=timeout)
        except queue.Empty:
            return None

    def send_command(self, cmd, value):
        value = value & 0xFFFFFF
        packet = bytes([cmd, (value>>16)&0xFF, (value>>8)&0xFF, value&0xFF])
        self.ser.write(packet)
        # Ожидаем 4 байта эха
        echo = []
        for _ in range(4):
            b = self.ser.read(1)
            if not b:
                print("Timeout waiting for echo")
                return False
            echo.append(b[0])
        expected = [cmd, (value>>16)&0xFF, (value>>8)&0xFF, value&0xFF]
        if echo == expected:
            print(f"Full echo OK: {''.join(f'{x:02X}' for x in echo)}")
            return True
        else:
            print(f"Echo mismatch: expected {expected}, got {echo}")
            return False

    def test_sweep(self, divider, steps=20, delay=0.2):
        print(f"Starting sweep with DIVIDER = {divider}")
        if not self.send_command(CMD_DIVIDER, divider):
            print("Failed to set DIVIDER, aborting sweep.")
            return

        step = max(1, divider // steps)
        for i in range(0, divider, step):
            if not self.send_command(CMD_DUTY, i):
                print(f"Failed at DUTY={i}, aborting.")
                return
            time.sleep(delay)

        for i in range(divider-1, -1, -step):
            if not self.send_command(CMD_DUTY, i):
                print(f"Failed at DUTY={i}, aborting.")
                return
            time.sleep(delay)

        print("Sweep completed.")

# ----------------------------------------------------------------------
# Интерфейс командной строки (без изменений, кроме подсказок)
# ----------------------------------------------------------------------
def interactive_mode(controller):
    print("\n=== PWM Interactive Control (Echo protocol) ===")
    print("Commands:")
    print("  divider <val>   - set divider (0-16777215)")
    print("  duty <val>      - set duty (0-16777215)")
    print("  sweep <divider> - run automatic brightness sweep")
    print("  quit            - exit")
    print()

    while True:
        try:
            line = input("> ").strip()
            if not line:
                continue
            parts = line.split()
            cmd = parts[0].lower()
            if cmd == "quit" or cmd == "exit":
                break
            elif cmd == "divider" and len(parts) == 2:
                val = int(parts[1])
                controller.send_command(CMD_DIVIDER, val)
            elif cmd == "duty" and len(parts) == 2:
                val = int(parts[1])
                controller.send_command(CMD_DUTY, val)
            elif cmd == "sweep" and len(parts) == 2:
                div = int(parts[1])
                controller.test_sweep(div)
            else:
                print("Unknown command. Available: divider, duty, sweep, quit")
        except KeyboardInterrupt:
            print("\nExiting.")
            break
        except ValueError:
            print("Invalid number.")

def main():
    parser = argparse.ArgumentParser(
        description="PWM Control over UART for FPGA (24-bit values, echo protocol)",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  pwm_control.py --port /dev/ttyUSB0 --duty 5000
  pwm_control.py --port /dev/ttyUSB0 --divider 10000 --duty 5000
  pwm_control.py --port COM3 --test --divider 20000
  pwm_control.py --port /dev/ttyUSB0 --interactive
        """
    )
    parser.add_argument("--port", required=True, help="Serial port (e.g., /dev/ttyUSB0, COM3)")
    parser.add_argument("--baud", type=int, default=115200, help="Baud rate (default 115200)")
    parser.add_argument("--divider", type=int, help="Set DIVIDER value (0-16777215)")
    parser.add_argument("--duty", type=int, help="Set DUTY value (0-16777215)")
    parser.add_argument("--test", action="store_true", help="Run automatic brightness sweep")
    parser.add_argument("--interactive", "-i", action="store_true", help="Interactive mode after initial settings")

    args = parser.parse_args()

    ctrl = PWMController(port=args.port, baudrate=args.baud)
    if not ctrl.open():
        sys.exit(1)

    try:
        if args.divider is not None:
            ctrl.send_command(CMD_DIVIDER, args.divider)
        if args.duty is not None:
            ctrl.send_command(CMD_DUTY, args.duty)

        if args.test:
            if args.divider is None:
                print("Please specify --divider for test.")
                sys.exit(1)
            ctrl.test_sweep(args.divider)

        if args.interactive or (args.divider is None and args.duty is None and not args.test):
            interactive_mode(ctrl)

    except KeyboardInterrupt:
        print("\nInterrupted.")
    finally:
        ctrl.close()
        print("Port closed.")

if __name__ == "__main__":
    main()

