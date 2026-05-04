# 🎛️ AKTools Modules

> Community-driven module registry for AKTools

[![Build Status](https://img.shields.io/github/actions/workflow/status/Akinus21/aktools-modules/build.yml?branch=main&style=flat-square)](https://github.com/Akinus21/aktools-modules/actions)
[![License](https://img.shields.io/badge/License-MIT-yellow?style=flat-square)](LICENSE)

Welcome to the AKTools Modules registry! 🎉 This repository hosts a growing collection of community modules that extend AKTools' functionality.

## ✨ Features

- 📦 **Modular Design** — Each module is self-contained with its own manifest and scripts
- 🔍 **Centralized Registry** — All available modules indexed in `registry.json`
- 🤝 **Easy Contribution** — Submit your own modules via pull requests
- ✅ **CI Validated** — Every module is validated for proper structure and XML syntax
- 🔄 **Auto-Updating** — Registry regenerates automatically when new modules are added

## 📁 Module Structure

```
module-name/
├── manifest.xml      # Module metadata
├── README.md         # Documentation
└── script.sh         # Executable (optional)
```

## 🚀 Quick Start

### Install a Module

```bash
aktools add-mod <module-id>
```

### Browse Available Modules

Check [`registry.json`](registry.json) for all available modules.

### Create Your Own Module

1. Create a folder with your module name
2. Add `manifest.xml` with your module metadata
3. Add `README.md` for documentation
4. Add any script files referenced in your manifest
5. Submit a pull request!

## 📋 Available Modules

| Module | Description | Author |
|--------|-------------|--------|
| 🐙 `git` | Git operations wrapper | Community |
| 🔍 `procfind` | Find processes by name | Community |
| 🌙 `noctalia` | Noctalia integration | Akinus21 |
| 🔐 `ssh` | SSH utilities | Community |
| 📝 `example-module` | Example template | AKTools |

*(Auto-generated from registry.json)*

## 🛠️ Development

### Local Development

```bash
# Clone the repository
git clone https://github.com/Akinus21/aktools-modules.git

# Add a new module
mkdir my-module && cd my-module
echo '<?xml version="1.0"?><module><name>my-module</name></module>' > manifest.xml

# Submit a PR!
```

### CI Pipeline

The repository uses GitHub Actions to:
- ✅ Validate all `manifest.xml` files
- ✅ Verify `registry.json` integrity
- 🔄 Auto-regenerate registry on module changes
- 📢 Notify webhook on validation failures

## 📜 License

Modules in this registry retain their individual licenses. The registry infrastructure is MIT licensed.

---

<div align="center">

**Made with ❤️ by the AKTools community**

</div>