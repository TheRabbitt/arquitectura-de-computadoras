#!/usr/bin/env python3
"""
Script para probar comunicación UART con la placa FPGA (Sistema UART-ALU)
Versión mejorada con mejor manejo de timing y debug
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
        
        # Esperar a que el puerto se estabilice
        time.sleep(0.1)
        
        # Limpiar buffers
        ser.reset_input_buffer()
        ser.reset_output_buffer()
        
        return ser
    except serial.SerialException as e:
        print(f"✗ Error al abrir puerto: {e}")
        return None


def send_operation(ser, operation_name, operand_a, operand_b, verbose=True):
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
        # Limpiar buffer de entrada antes de enviar
        ser.reset_input_buffer()
        
        # Enviar los 3 bytes
        ser.write(data)
        ser.flush()
        
        if verbose:
            print(f"\n[TX] Enviando operación:")
            print(f"  Operación: {operation_name} (0x{opcode:02X})")
            print(f"  Operando A: {operand_a} (0x{operand_a:02X})")
            print(f"  Operando B: {operand_b} (0x{operand_b:02X})")
            print(f"  Bytes enviados: {' '.join([f'0x{b:02X}' for b in data])}")
        
        return True
    except serial.SerialException as e:
        print(f"✗ Error al escribir: {e}")
        return False


def receive_result(ser, verbose=True):
    """
    Recibe el resultado y los flags de la placa
    Formato: [resultado (1 byte)] [flags (1 byte)]
    Flags: {6'b0, carry, zero}
    """
    try:
        # Esperar un momento para que la FPGA procese
        time.sleep(0.2)
        
        # Verificar cuántos bytes hay disponibles
        available = ser.in_waiting
        if verbose:
            print(f"\n[RX] Bytes disponibles en buffer: {available}")
        
        # Leer resultado (primer byte)
        data1 = ser.read(1)
        
        if len(data1) < 1:
            print(f"✗ Timeout: No se recibió byte de resultado")
            return None, None, None
        
        result = data1[0]
        
        # Pequeña pausa entre lecturas
        time.sleep(0.05)
        
        # Leer flags (segundo byte)
        data2 = ser.read(1)
        
        if len(data2) < 1:
            print(f"✗ Timeout: No se recibió byte de flags")
            return result, None, None
        
        flags = data2[0]
        carry = (flags & 0x02) >> 1
        zero =  flags & 0x01
        
        if verbose:
            print(f"\n[RX] Resultado recibido:")
            print(f"  Resultado: {result} (0x{result:02X}, {result:08b}b)")
            print(f"  Flags byte: 0x{flags:02X} ({flags:08b}b)")
            print(f"  Bit 0 (Zero): {zero}")
            print(f"  Bit 1 (Carry):  {carry}")
        
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
            import traceback
            traceback.print_exc()


def automated_test(ser):
    """Ejecuta pruebas automatizadas"""
    # Formato: (operación, a, b, resultado_esperado, carry_esperado, zero_esperado)
    tests = [
        ("ADD", 5, 3, 8, 0, 0),         # 5 + 3 = 8, sin carry, sin zero
        ("SUB", 10, 4, 6, 0, 0),        # 10 - 4 = 6, sin carry, sin zero
        ("AND", 0xAA, 0x55, 0, 1, 0),   # 0xAA & 0x55 = 0, sin carry, zero=1
        ("OR", 0x0F, 0xF0, 0xFF, 0, 0), # 0x0F | 0xF0 = 0xFF, sin carry, sin zero
        ("XOR", 0xFF, 0xFF, 0, 1, 0),   # 0xFF ^ 0xFF = 0, sin carry, zero=1
        ("ADD", 127, 1, 128, 0, 1),     # 127 + 1 = 128, carry=1 (overflow), sin zero
    ]
    
    print("\n" + "="*60)
    print("PRUEBAS AUTOMATIZADAS")
    print("="*60)
    
    # Limpiar buffers al inicio
    ser.reset_input_buffer()
    ser.reset_output_buffer()
    time.sleep(0.1)
    
    passed = 0
    failed = 0
    
    for i, (op, a, b, expected_result, expected_zero, expected_carry) in enumerate(tests, 1):
        print(f"\n{'='*60}")
        print(f"Prueba {i}/{len(tests)}: {op} ({a} {op} {b})")
        print(f"{'='*60}")
        
        if send_operation(ser, op, a, b, verbose=True):
            result, carry, zero = receive_result(ser, verbose=True)
            
            if result is not None:
                result_ok = (result == expected_result)
                carry_ok = (carry == expected_carry)
                zero_ok = (zero == expected_zero)
                
                print(f"\nVerificación:")
                print(f"  Resultado: {result} {'✓' if result_ok else '✗'} (esperado: {expected_result})")
                print(f"  Carry:     {carry} {'✓' if carry_ok else '✗'} (esperado: {expected_carry})")
                print(f"  Zero:      {zero} {'✓' if zero_ok else '✗'} (esperado: {expected_zero})")
                
                if result_ok and carry_ok and zero_ok:
                    print("\n✓ PASS")
                    passed += 1
                else:
                    print("\n✗ FAIL")
                    failed += 1
            else:
                print("✗ FAIL (no response)")
                failed += 1
        else:
            print("✗ FAIL (send error)")
            failed += 1
        
        # Pausa entre pruebas
        time.sleep(0.5)
    
    print("\n" + "="*60)
    print(f"Resultados: {passed} pasadas, {failed} fallidas")
    print(f"Tasa de éxito: {100*passed/(passed+failed):.1f}%")
    print("="*60)


def main():
    """Función principal"""
    print("="*60)
    print("UART-ALU Test Tool - Versión Mejorada")
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