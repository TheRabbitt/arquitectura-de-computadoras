#!/usr/bin/env python3
"""
Script para probar comunicación UART con la placa FPGA (Sistema UART-ALU)
Permite enviar operaciones y recibir resultados
"""

import serial
import time
import sys

# Configuración
BAUD_RATE = 19200
TIMEOUT = 2  # segundos

# Códigos de operación
OPERATIONS = {
    'ADD': 0x20,
    'SUB': 0x22,
    'AND': 0x24,
    'OR':  0x25,
    'XOR': 0x26,
    'NOR': 0x27,
    'SRL': 0x02,
    'SRA': 0x03,
}


def list_ports():
    """Lista los puertos seriales disponibles"""
    import platform
    
    if platform.system() == 'Windows':
        import subprocess
        result = subprocess.run(['wmic', 'logicaldisk', 'get', 'name'], 
                              capture_output=True, text=True)
        print("Puertos COM disponibles en Windows:")
        print("COM1, COM3, COM4, COM5... (revisa Device Manager)")
    else:
        import subprocess
        result = subprocess.run(['ls', '/dev/tty*'], 
                              capture_output=True, text=True, shell=True)
        print("Puertos disponibles en Linux:")
        print(result.stdout)


def open_serial_port(port_name):
    """Abre el puerto serial"""
    try:
        ser = serial.Serial(
            port=port_name,
            baudrate=BAUD_RATE,
            timeout=TIMEOUT,
            bytesize=serial.EIGHTBITS,
            parity=serial.PARITY_NONE,
            stopbits=serial.STOPBITS_ONE
        )
        print(f"✓ Puerto {port_name} abierto correctamente")
        print(f"  Baudrate: {BAUD_RATE} bps")
        return ser
    except serial.SerialException as e:
        print(f"✗ Error al abrir puerto: {e}")
        return None


def send_operation(ser, operation_name, operand_a, operand_b):
    """
    Envía una operación a la placa
    Formato: [opcode (1 byte)] [operand_a (1 byte)] [operand_b (1 byte)]
    """
    if operation_name not in OPERATIONS:
        print(f"✗ Operación desconocida: {operation_name}")
        print(f"  Operaciones disponibles: {', '.join(OPERATIONS.keys())}")
        return False
    
    opcode = OPERATIONS[operation_name]
    
    # Crear los 3 bytes
    data = bytes([opcode, operand_a & 0xFF, operand_b & 0xFF])
    
    try:
        ser.write(data)
        print(f"\n[TX] Enviando operación:")
        print(f"  Operación: {operation_name} (0x{opcode:02X})")
        print(f"  Operando A: {operand_a} (0x{operand_a:02X})")
        print(f"  Operando B: {operand_b} (0x{operand_b:02X})")
        return True
    except serial.SerialException as e:
        print(f"✗ Error al escribir: {e}")
        return False


def receive_result(ser):
    """
    Recibe el resultado y los flags de la placa
    Formato: [resultado (1 byte)] [flags (1 byte)]
    Flags: {6'b0, carry, zero}
    """
    try:
        # Esperar el resultado (1 byte)
        result_byte = ser.read(1)
        if not result_byte:
            print("✗ Timeout esperando resultado")
            return None, None, None
        
        result = result_byte[0]
        
        # Esperar los flags (1 byte)
        flags_byte = ser.read(1)
        if not flags_byte:
            print("✗ Timeout esperando flags")
            return result, None, None
        
        flags = flags_byte[0]
        carry = flags & 0x01
        zero = (flags >> 1) & 0x01
        
        print(f"\n[RX] Resultado recibido:")
        print(f"  Resultado: {result} (0x{result:02X})")
        print(f"  Carry flag: {carry}")
        print(f"  Zero flag: {zero}")
        
        return result, carry, zero
    except serial.SerialException as e:
        print(f"✗ Error al leer: {e}")
        return None, None, None


def print_menu():
    """Muestra el menú de operaciones"""
    print("\n" + "="*50)
    print("OPERACIONES DISPONIBLES")
    print("="*50)
    for op, code in OPERATIONS.items():
        print(f"  {op:3} (0x{code:02X})")
    print("="*50)


def interactive_mode(ser):
    """Modo interactivo para pruebas"""
    while True:
        try:
            print("\n1. Enviar operación")
            print("2. Ver operaciones disponibles")
            print("3. Test automatizado")
            print("4. Salir")
            
            choice = input("\nSelecciona opción (1-4): ").strip()
            
            if choice == '1':
                print("\nOperaciones disponibles:")
                for op in OPERATIONS.keys():
                    print(f"  - {op}")
                
                op_name = input("Operación: ").strip().upper()
                
                try:
                    a = int(input("Operando A (0-255): ").strip())
                    b = int(input("Operando B (0-255): ").strip())
                    
                    if not (0 <= a <= 255 and 0 <= b <= 255):
                        print("✗ Los operandos deben estar entre 0 y 255")
                        continue
                    
                    if send_operation(ser, op_name, a, b):
                        time.sleep(0.5)  # Esperar a que se procese
                        result, carry, zero = receive_result(ser)
                        
                        if result is not None:
                            print(f"\n✓ Operación completada exitosamente")
                
                except ValueError:
                    print("✗ Entrada inválida")
            
            elif choice == '2':
                print_menu()
            
            elif choice == '3':
                automated_test(ser)
            
            elif choice == '4':
                print("\nSaliendo...")
                break
            
            else:
                print("✗ Opción no válida")
        
        except KeyboardInterrupt:
            print("\n\nInterrumpido por usuario")
            break
        except Exception as e:
            print(f"✗ Error: {e}")


def automated_test(ser):
    """Ejecuta pruebas automatizadas"""
    tests = [
        ("ADD", 5, 3, 8, 0, 0),         # 5 + 3 = 8
        ("SUB", 10, 4, 6, 0, 0),        # 10 - 4 = 6
        ("AND", 0xAA, 0x55, 0, 0, 1),   # 0xAA & 0x55 = 0 (zero flag)
        ("OR", 0x0F, 0xF0, 0xFF, 0, 0), # 0x0F | 0xF0 = 0xFF
        ("XOR", 0xFF, 0xFF, 0, 0, 1),   # 0xFF ^ 0xFF = 0 (zero flag)
        ("ADD", 127, 1, 128, 1, 0),     # 127 + 1 = 128 (overflow)
    ]
    
    print("\n" + "="*60)
    print("PRUEBAS AUTOMATIZADAS")
    print("="*60)
    
    passed = 0
    failed = 0
    
    for i, (op, a, b, expected_result, expected_carry, expected_zero) in enumerate(tests, 1):
        print(f"\nPrueba {i}: {op} ({a} {op} {b})")
        
        if send_operation(ser, op, a, b):
            time.sleep(0.5)
            result, carry, zero = receive_result(ser)
            
            if result is not None:
                result_ok = (result == expected_result)
                carry_ok = (carry == expected_carry)
                zero_ok = (zero == expected_zero)
                
                if result_ok and carry_ok and zero_ok:
                    print("✓ PASS")
                    passed += 1
                else:
                    print("✗ FAIL")
                    if not result_ok:
                        print(f"    Resultado: esperado {expected_result}, obtuvo {result}")
                    if not carry_ok:
                        print(f"    Carry: esperado {expected_carry}, obtuvo {carry}")
                    if not zero_ok:
                        print(f"    Zero: esperado {expected_zero}, obtuvo {zero}")
                    failed += 1
            else:
                print("✗ FAIL (no response)")
                failed += 1
    
    print("\n" + "="*60)
    print(f"Resultados: {passed} pasadas, {failed} fallidas")
    print("="*60)


def main():
    """Función principal"""
    print("="*60)
    print("UART-ALU Test Tool")
    print("="*60)
    
    if len(sys.argv) > 1:
        port = sys.argv[1]
    else:
        print("\nUso: python uart_test.py <puerto_serial>")
        print("\nEjemplos:")
        print("  Windows:  python uart_test.py COM5")
        print("  Linux:    python uart_test.py /dev/ttyUSB0")
        print("\nPuertos disponibles:")
        list_ports()
        print("\nEscribe el puerto serial (ej: COM5, /dev/ttyUSB0):")
        port = input().strip()
    
    ser = open_serial_port(port)
    if not ser:
        return
    
    try:
        interactive_mode(ser)
    finally:
        ser.close()
        print("Puerto cerrado")


if __name__ == "__main__":
    main()