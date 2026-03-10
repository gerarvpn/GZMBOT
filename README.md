# GZMBOT - WhatsApp Business Automation Platform 🤖

![GZMBOT Panel](https://via.placeholder.com/800x400?text=GZMBOT+Panel+Screenshot)

> **GZMBOT** es una solución empresarial para automatizar conversaciones de WhatsApp con un panel de control moderno, gestión de respuestas automáticas, recordatorios, y copias de seguridad. Diseñado para negocios que buscan eficiencia y profesionalismo en su comunicación.

---

## ✨ Características Principales

- **Panel de Control Moderno** – Interfaz elegante y responsiva con modo oscuro.
- **Conexión Segura con WhatsApp** – Vincula tu número mediante código QR (usando `whatsapp-web.js`).
- **Gestión de Respuestas Automáticas** – Configura palabras clave y respuestas (texto, imágenes, videos).
- **Bandeja de Aprendizaje** – Almacena mensajes no reconocidos para entrenar al bot.
- **Recordatorios Programados** – Envía mensajes automáticos en fechas específicas (único, diario, semanal, mensual, anual).
- **Cola de Mensajes Inteligente** – Evita bloqueos con intervalos configurables.
- **Números Excluidos** – Bloquea contactos específicos.
- **Backups Automáticos** – Copia de seguridad diaria a las 12:00 AM (hora República Dominicana) y envío opcional por WhatsApp.
- **Configuración en Tiempo Real** – Cambia credenciales, número de backup, retardo de respuestas e intervalo de cola sin reiniciar.
- **Dominio Personalizado con SSL** – Integración automática con Let's Encrypt.
- **Monitorización en Vivo** – Estado de conexión, estadísticas de mensajes y tamaño de la cola mediante WebSockets.

---

## 🖥️ Vista Previa del Panel

![Dashboard](https://via.placeholder.com/800x400?text=Dashboard)
![Conexión QR](https://via.placeholder.com/800x400?text=QR+Connection)
![Gestión de Respuestas](https://via.placeholder.com/800x400?text=Training+Section)

> *Nota: Reemplaza las imágenes con capturas reales de tu instalación.*

---

## 📋 Requisitos Previos

- Servidor con **Ubuntu 20.04 / 22.04** (se recomienda un VPS con al menos 2 GB de RAM).
- **Dominio propio** apuntando al servidor (para SSL).
- Acceso **root** o usuario con permisos sudo.

---

## 🚀 Instalación Rápida (Una línea)

Ejecuta el siguiente comando en tu servidor como **root**:

```bash
bash <(curl -Ls https://raw.githubusercontent.com/gerarvpn/GZMBOT/main/instalar)