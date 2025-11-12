# Configuration Examples and Usage Guide

This document describes how to use the flexible configuration system for the datamover HWPE project.

## 🚀 Quick Commands

```bash
# Show configuration help
make help

# Validate current config
make validate-config

# Run with preset
make sim CONFIG_PRESET=small-matrix

# Override specific parameter
make sim CONFIG_PRESET=transpose-test TRANSP_MODE=4

# Test all presets
make test-all-presets

# Test transpose modes
make test-transpose-modes

# Test configuration combinations (grid)
make test-transpose-grid
make test-cim-grid
```

## Quick Start

### Using Configuration Presets

Run simulations with predefined configurations:

```bash
# Small matrix for quick testing
make sim CONFIG_PRESET=small-matrix

# Medium matrix for moderate testing
make sim CONFIG_PRESET=medium-matrix

# Large matrix for stress testing
make sim CONFIG_PRESET=large-matrix

# Transpose-focused testing
make sim CONFIG_PRESET=transpose-test

# Rectangular matrix testing
make sim CONFIG_PRESET=rect-wide
make sim CONFIG_PRESET=rect-tall
make sim CONFIG_PRESET=rect-narrow
make sim CONFIG_PRESET=rect-elongated

# Copy mode testing
make sim CONFIG_PRESET=copy-small
make sim CONFIG_PRESET=copy-medium

# CIM mode testing
make sim CONFIG_PRESET=cim-small
make sim CONFIG_PRESET=cim-medium
make sim CONFIG_PRESET=cim-large
```

### Command Line Overrides

Override specific parameters while keeping preset base:

```bash
# Use small-matrix preset but change transpose mode
make sim CONFIG_PRESET=small-matrix TRANSP_MODE=2

# Use medium-matrix preset but different element width
make sim CONFIG_PRESET=medium-matrix ELEM_WIDTH=16

# Override matrix dimensions
make sim CONFIG_PRESET=transpose-test MATRIX_SIZE_M=64 MATRIX_SIZE_N=64
```

### Custom Configuration

Use completely custom parameters:

```bash
# Custom configuration via command line
make sim CONFIG_PRESET=custom BANDWIDTH=512 ELEM_WIDTH=16 MATRIX_SIZE_M=128 MATRIX_SIZE_N=128

# Or edit config.mk for persistent custom settings
make sim CONFIG_PRESET=custom
```

## Configuration Hierarchy

Parameters are resolved in this order (highest priority first):

1. **Command line arguments**: `make sim TRANSP_MODE=2`
2. **Preset definitions**: Values from config_presets.mk
3. **Default values**: Fallback values in config.mk

## Available Presets

| Preset | Description | Matrix Size | Memory | Mode |
|--------|-------------|-------------|--------|------|
| `small-matrix` | Quick testing | 4x4 | 2KB | Transpose |
| `medium-matrix` | Moderate testing | 64x64 | 16KB | Transpose |
| `large-matrix` | Stress testing | 448x448 | 512KB | Transpose |
| `transpose-test` | Transpose focus | 32x32 | 64KB | Transpose |
| `rect-wide` | Wide rectangle | 64x256 | 128KB | Transpose |
| `rect-tall` | Tall rectangle | 256x64 | 128KB | Transpose |
| `rect-narrow` | Narrow rectangle | 16x128 | 32KB | Transpose |
| `rect-elongated` | Elongated rectangle | 128x32 | 64KB | Transpose |
| `copy-small` | Copy mode testing | 4x4 | 2KB | Copy |
| `copy-medium` | Copy mode testing | 64x64 | 16KB | Copy |
| `cim-small` | CIM mode testing | 32x128 | 32KB | CIM |
| `cim-medium` | CIM mode testing | 64x256 | 64KB | CIM |
| `cim-large` | CIM mode testing | 128x512 | 256KB | CIM |
| `custom` | User-defined | Variable | Variable | Variable |

## � Datamover Modes

The datamover supports three main operation modes:

### Copy Mode (DATAMOVER_MODE=0)
- **Purpose**: Direct memory-to-memory copy operations
- **Use case**: Basic data movement without transformation
- **Presets**: `copy-small`, `copy-medium`
- **Example**: `make sim CONFIG_PRESET=copy-small`

### Transpose Mode (DATAMOVER_MODE=1)
- **Purpose**: Matrix transposition during data movement
- **Use case**: Data layout transformations for optimized access patterns
- **Transpose elements**: 1, 2, or 4 elements per cycle (`TRANSP_MODE`)
- **Presets**: `small-matrix`, `medium-matrix`, `large-matrix`, `transpose-test`, `rect-*`
- **Example**: `make sim CONFIG_PRESET=transpose-test TRANSP_MODE=2`

### CIM Mode (DATAMOVER_MODE=2)
- **Purpose**: Compute-In-Memory data layout conversion
- **Use case**: Converting row-major data to CIM accelerator layouts
- **CIM layouts**: A-Layout (`CIM_MODE=0`) or B-Layout (`CIM_MODE=1`)
- **Dimensions**: Configurable `CIM_INNER_DIM` and `CIM_OUTER_DIM`
- **Presets**: `cim-small`, `cim-medium`, `cim-large`
- **Example**: `make sim CONFIG_PRESET=cim-medium`

##  Key Parameters

| Parameter | Values | Description |
|-----------|---------|-------------|
| `DATAMOVER_MODE` | 0,1,2 | Operation mode (0=Copy, 1=Transpose, 2=CIM) |
| `TRANSP_MODE` | 0,1,2,4 | Transpose elements per cycle |
| `CIM_MODE` | 0,1 | CIM layout (0=A-Layout, 1=B-Layout) |
| `CIM_INNER_DIM` | 32,64,... | CIM inner dimension in elements |
| `CIM_OUTER_DIM` | 16,32,64,... | CIM outer dimension in elements |
| `ELEM_WIDTH` | 8 | Element width in bits |
| `BANDWIDTH` | 64,128,256,512,1024 | Memory bandwidth in bits |
| `MATRIX_SIZE_M` | Any | Matrix height in elements |
| `MATRIX_SIZE_N` | Any | Matrix width in elements |
| `MEMORY_SIZE` | Any | Available memory in words |
| `WORD_WIDTH` | 16,32,64 | Word width in bits (typically 32) |

## Built-in Test Targets

The system provides several built-in test targets for comprehensive testing:

```bash
# Test all available presets with detailed reporting (continues through failures)
make test-all-presets

# Test all transpose modes with transpose-test preset
make test-transpose-modes

# Test configuration parameter combinations (bandwidth/transpose/word width grid)
make test-transpose-grid

# Test CIM configuration parameter combinations (bandwidth/CIM dimensions/word width grid)
make test-cim-grid

# Validate configuration without running simulation
make validate-config CONFIG_PRESET=<preset-name>
```

## Creating New Presets

Add new presets to `config_presets.mk`:

```makefile
ifeq ($(CONFIG_PRESET),my-test)
    BANDWIDTH = 1024
    WORD_WIDTH = 32
    ELEM_WIDTH = 16
    MEMORY_SIZE = 32768
    TRANSP_MODE = 4
    MATRIX_SIZE_M = 64
    MATRIX_SIZE_N = 32
    CONFIG_DESC = "Custom test for specific use case"
endif
```

## Advanced Usage

### Environment-based Configuration

Set up your shell environment:

```bash
# Set default preset for your session
export CONFIG_PRESET=transpose-test

# Override specific parameters
export TRANSP_MODE=4
export ELEM_WIDTH=16

# Run simulation with environment settings
make sim
```

### Makefile Integration

The system includes the following built-in test targets:

```makefile
# Built-in targets (already available)
test-all-presets:
	# Tests all 8 configuration presets (stops on first failure)
	$(MAKE) sim CONFIG_PRESET=small-matrix
	$(MAKE) sim CONFIG_PRESET=medium-matrix
	$(MAKE) sim CONFIG_PRESET=large-matrix
	$(MAKE) sim CONFIG_PRESET=transpose-test
	$(MAKE) sim CONFIG_PRESET=rect-wide
	$(MAKE) sim CONFIG_PRESET=rect-tall
	$(MAKE) sim CONFIG_PRESET=rect-narrow
	$(MAKE) sim CONFIG_PRESET=rect-elongated

test-all-presets:
	# Tests all presets with detailed reporting (continues through failures)
	# Provides summary of which tests passed/failed

test-transpose-modes:
	# Tests all transpose modes (0,1,2,4)
	$(MAKE) sim CONFIG_PRESET=transpose-test TRANSP_MODE=0
	$(MAKE) sim CONFIG_PRESET=transpose-test TRANSP_MODE=1
	$(MAKE) sim CONFIG_PRESET=transpose-test TRANSP_MODE=2
	$(MAKE) sim CONFIG_PRESET=transpose-test TRANSP_MODE=4
```

For additional custom test suites, you can create your own targets:

```makefile
# Add to your Makefile for custom test suites
test-custom-suite:
	@echo "Testing custom configuration suite..."
	$(MAKE) sim CONFIG_PRESET=small-matrix TRANSP_MODE=2
	$(MAKE) sim CONFIG_PRESET=medium-matrix ELEM_WIDTH=16
	$(MAKE) sim CONFIG_PRESET=custom BANDWIDTH=1024 MATRIX_SIZE_M=64 MATRIX_SIZE_N=64
```

### Configuration Validation

The system includes automatic validation:

- TRANSP_MODE must be 0, 1, 2, or 4
- Matrix dimensions must fit in available memory
- Bandwidth and element width must be compatible

### Debug Configuration

To see all computed values and configuration info:

```bash
# Show configuration details
make help

# Validate configuration with detailed output
make validate-config CONFIG_PRESET=small-matrix

# Enable debug output in config.mk (uncomment $(info) lines)
make sim CONFIG_PRESET=small-matrix | grep -E "(BANDWIDTH|MATRIX|STIM)"
```

## 💡 Usage Patterns

```bash
# Development cycle
make sim CONFIG_PRESET=small-matrix      # Quick check
make sim CONFIG_PRESET=transpose-test    # Feature test
make sim CONFIG_PRESET=large-matrix      # Stress test

# Research/tuning
make sim CONFIG_PRESET=custom BANDWIDTH=1024 ELEM_WIDTH=32

# Validation and help
make validate-config CONFIG_PRESET=transpose-test
make help
```

## Tips and Best Practices

1. **Start Small**: Use `small-matrix` for initial testing, then scale up
2. **Test Transpose**: Use `transpose-test` preset for transpose functionality
3. **Rectangular Testing**: Use rectangular presets (`rect-wide`, `rect-tall`, etc.) for non-square matrices
4. **Parameter Validation**: Always run `make validate-config` to check computed values
5. **Documentation**: Document custom presets with clear descriptions
6. **Memory Requirements**: Ensure matrix dimensions fit within available memory
7. **Bandwidth Alignment**: Both matrix dimensions should be ≥ BANDWIDTH/ELEM_WIDTH

## Example Workflows

### Development Workflow
```bash
# Quick functionality check
make sim CONFIG_PRESET=small-matrix

# Detailed transpose testing
make sim CONFIG_PRESET=transpose-test

# Stress testing with large matrices
make sim CONFIG_PRESET=large-matrix
```

### CI/Testing Workflow
```bash
# Comprehensive test suite with detailed reporting
make test-all-presets

# Test specific functionality
make test-transpose-modes

# Comprehensive parameter grid testing
make test-transpose-grid
make test-cim-grid
```

### Custom Research Configuration
```bash
# Specific research parameters
make sim CONFIG_PRESET=custom \
    BANDWIDTH=1024 \
    ELEM_WIDTH=32 \
    MATRIX_SIZE_M=256 \
    MATRIX_SIZE_N=128 \
    TRANSP_MODE=4
```

## 🔍 System Files

The configuration system consists of these key files:

- **`config.mk`** - Main configuration with default values and computed parameters
- **`config_presets.mk`** - Preset definitions for common test scenarios
- **`Makefile`** - Enhanced targets including test-all-presets and validation
- **`verif/python/validate_config.py`** - Python validation script for parameter checking
- **`CONFIG_USAGE.md`** - This comprehensive documentation file

## Troubleshooting

### Common Issues

1. **Invalid TRANSP_MODE**: Must be 0, 1, 2, or 4
   ```bash
   make validate-config CONFIG_PRESET=my-preset  # Check for errors
   ```

2. **Memory insufficient**: Matrix too large for available memory
   ```bash
   # Reduce matrix size or increase MEMORY_SIZE
   make sim CONFIG_PRESET=small-matrix  # Use smaller preset
   ```

3. **Bandwidth alignment warnings**: Matrix dimensions not aligned to bandwidth
   ```bash
   # Adjust matrix dimensions to be multiples of BANDWIDTH/ELEM_WIDTH
   make sim MATRIX_SIZE_M=32 MATRIX_SIZE_N=32  # Use aligned dimensions
   ```

4. **Configuration not taking effect**: Check parameter precedence
   ```bash
   # Command line overrides presets
   make sim CONFIG_PRESET=small-matrix TRANSP_MODE=2  # Override works
   ```
