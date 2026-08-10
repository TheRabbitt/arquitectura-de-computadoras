# Arquitectura de Computadoras - TPs Integrados

🎯 **Repositorio de Trabajos Prácticos de Arquitectura de Computadoras**

Este repositorio contiene una serie de 3 trabajos prácticos integrados que construyen progresivamente un sistema completo desde componentes básicos hasta un procesador RISC-V funcional.

## 🚀 Descripción General

### Estructura Progresiva
1. **TP1 - ALU**: Unidad Aritmético-Lógica con operaciones básicas
2. **TP2 - UART**: Comunicación serie + Integración con ALU
3. **TP3 - CPU RISC-V**: Procesador completo + ALU + UART

### Tecnologías
- **HDL**: Verilog
- **Simulación**: ModelSim/Vivado/Icarus Verilog
- **FPGA**: Compatible con Xilinx/Intel/Lattice
- **ISA**: RISC-V RV32I

## 📁 Estructura del Repositorio

```
├── TP1-ALU/           # Unidad Aritmético-Lógica
├── TP2-UART/          # Comunicación Serie + ALU
├── TP3-CPU-RISCV/     # Procesador RISC-V Completo
├── docs/              # Documentación detallada
├── common/            # Componentes compartidos
└── scripts/           # Scripts de automatización
```

## 🎯 Objetivos de Aprendizaje

- **Diseño Digital**: Implementación de circuitos digitales complejos
- **HDL**: Programación en Verilog/SystemVerilog
- **Arquitectura**: Comprensión de arquitecturas de procesadores
- **Comunicación**: Protocolos de comunicación serie
- **Integración**: Desarrollo modular e integración de sistemas
- **RISC-V**: Implementación de arquitectura RISC-V

## 🏁 Quick Start

### Prerrequisitos
```bash
# Herramientas necesarias
- Git
- Simulador Verilog (ModelSim, Vivado, Icarus)
- Editor de texto/IDE
- FPGA toolkit (opcional, para síntesis)
```

### Clonar el repositorio
```bash
git clone https://github.com/tu-usuario/arquitectura-computadoras.git
cd arquitectura-computadoras
```

### Ejecutar simulaciones
```bash
# TP1 - ALU
cd TP1-ALU
./scripts/simulate.sh

# TP2 - UART + ALU
cd ../TP2-UART  
./scripts/simulate.sh

# TP3 - CPU completo
cd ../TP3-CPU-RISCV
./scripts/simulate.sh
```

## 📋 Estado del Proyecto

### TP1 - ALU ✅
- [x] Operaciones aritméticas (ADD, SUB, MUL, DIV)
- [x] Operaciones lógicas (AND, OR, XOR, NOT)
- [x] Operaciones de desplazamiento (SLL, SRL, SRA)
- [x] Operaciones de comparación (EQ, LT, GT)
- [x] Testbench completo
- [x] Documentación

### TP2 - UART 🚧
- [ ] Módulo UART TX
- [ ] Módulo UART RX  
- [ ] Integración con ALU
- [ ] Protocolo de comunicación
- [ ] Testing

### TP3 - CPU RISC-V 📋
- [ ] Datapath design
- [ ] Control Unit
- [ ] Instruction Memory
- [ ] Register File
- [ ] Integración completa
- [ ] Programas de prueba

## 🔧 Desarrollo

### Estructura de Branches
- `main`: Código estable y funcional
- `tp1-dev`: Desarrollo TP1
- `tp2-dev`: Desarrollo TP2  
- `tp3-dev`: Desarrollo TP3
- `feature/nombre`: Features específicas

### Convenciones de Commits
```
[TP1] Add ALU basic operations
[TP2] Integrate UART with ALU module  
[TP3] Implement RISC-V instruction fetch
```

### Testing
Cada TP incluye:
- Testbenches unitarios
- Testbenches de integración
- Scripts de automatización
- Reportes de coverage

## 📚 Documentación

- [📖 TP1 - ALU Documentation](./docs/TP1-ALU.md)
- [📖 TP2 - UART Documentation](./docs/TP2-UART.md)
- [📖 TP3 - CPU Documentation](./docs/TP3-CPU-RISCV.md)

## 🎓 Recursos de Aprendizaje

### RISC-V
- [RISC-V Instruction Set Manual](https://riscv.org/specifications/)
- [RISC-V Assembly Programming](https://github.com/riscv/riscv-asm-manual)

### Verilog
- [Verilog Tutorial - ASIC World](https://www.asic-world.com/verilog/index.html)
- [Verilog by Example](https://www.doulos.com/knowhow/verilog/)

### UART
- [UART Protocol Guide](https://www.analog.com/en/analog-dialogue/articles/uart-a-hardware-communication-protocol.html)

## 👥 Contribución

1. Fork del repositorio
2. Crear branch para feature: `git checkout -b feature/nueva-caracteristica`
3. Commit cambios: `git commit -am 'Add nueva caracteristica'`
4. Push al branch: `git push origin feature/nueva-caracteristica`
5. Crear Pull Request

## 📄 Licencia

Este proyecto está bajo la licencia MIT - ver el archivo [LICENSE](LICENSE) para detalles.

## 📞 Contacto

- **Estudiantes**: [Ezequiel Matias Landaeta,David Aguero]
- **Email**: ezequiel.landaeta@unc.edu.ar,david.aguero@unc.edu.ar
- **Universidad**: [Universidad Nacional de Córdoba]
- **Materia**: Arquitectura de Computadoras

---

*Desarrollado como parte del curso de Arquitectura de Computadoras*