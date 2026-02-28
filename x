#!/bin/bash

# ============================================================
#    ██████╗ ███████╗███╗   ███╗██████╗  ██████╗ ████████╗
#   ██╔════╝ ╚══███╔╝████╗ ████║██╔══██╗██╔═══██╗╚══██╔══╝
#   ██║  ███╗  ███╔╝ ██╔████╔██║██████╔╝██║   ██║   ██║   
#   ██║   ██║ ███╔╝  ██║╚██╔╝██║██╔══██╗██║   ██║   ██║   
#   ╚██████╔╝███████╗██║ ╚═╝ ██║██████╔╝╚██████╔╝   ██║   
#    ╚═════╝ ╚══════╝╚═╝     ╚═╝╚═════╝  ╚═════╝    ╚═╝   
#                                                          
#   ███████╗███╗   ██╗████████╗███████╗██████╗ ██████╗ ██╗███████╗███████╗
#   ██╔════╝████╗  ██║╚══██╔══╝██╔════╝██╔══██╗██╔══██╗██║██╔════╝██╔════╝
#   █████╗  ██╔██╗ ██║   ██║   █████╗  ██████╔╝██████╔╝██║█████╗  █████╗  
#   ██╔══╝  ██║╚██╗██║   ██║   ██╔══╝  ██╔══██╗██╔═══╝ ██║██╔══╝  ██╔══╝  
#   ███████╗██║ ╚████║   ██║   ███████╗██║  ██║██║     ██║███████╗███████╗
#   ╚══════╝╚═╝  ╚═══╝   ╚═╝   ╚══════╝╚═╝  ╚═╝╚═╝     ╚═╝╚══════╝╚══════╝
# ============================================================
#   INSTALACIÓN PROFESIONAL - EDICIÓN ENTERPRISE (CORREGIDA)
#   Optimizado para Debian/Ubuntu - QR garantizado
# ============================================================

set -e  # Detener en caso de error

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color

# Función para imprimir con borde
print_step() {
    echo -e "${CYAN}┌──────────────────────────────────────────────┐${NC}"
    echo -e "${CYAN}│${NC} ${WHITE}$1${NC}"
    echo -e "${CYAN}└──────────────────────────────────────────────┘${NC}"
}

# Función para imprimir éxito
print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

# Función para imprimir advertencia
print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

# Función para imprimir error
print_error() {
    echo -e "${RED}❌ $1${NC}"
}

# Función para imprimir información
print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

# Limpiar pantalla
clear

# Mostrar banner
echo -e "${MAGENTA}"
echo '    ██████╗ ███████╗███╗   ███╗██████╗  ██████╗ ████████╗'
echo '   ██╔════╝ ╚══███╔╝████╗ ████║██╔══██╗██╔═══██╗╚══██╔══╝'
echo '   ██║  ███╗  ███╔╝ ██╔████╔██║██████╔╝██║   ██║   ██║   '
echo '   ██║   ██║ ███╔╝  ██║╚██╔╝██║██╔══██╗██║   ██║   ██║   '
echo '   ╚██████╔╝███████╗██║ ╚═╝ ██║██████╔╝╚██████╔╝   ██║   '
echo '    ╚═════╝ ╚══════╝╚═╝     ╚═╝╚═════╝  ╚═════╝    ╚═╝   '
echo -e "${NC}"
echo -e "${WHITE}                     ENTERPRISE EDITION${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}        Instalación Profesional - Debian/Ubuntu${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}\n"

# Verificar ejecución como root
if [[ $EUID -ne 0 ]]; then
   print_error "Este script debe ejecutarse como root (sudo)"
   exit 1
fi

# Solicitar credenciales
print_step "CONFIGURACIÓN DE ACCESO"

read -p "$(echo -e ${WHITE}👤 Usuario Maestro: ${NC})" ADMIN_USER
read -sp "$(echo -e ${WHITE}🔐 Contraseña Maestra: ${NC})" ADMIN_PASS
echo -e "\n"

print_success "Credenciales guardadas"

# ==================== FUNCIÓN DE DIAGNÓSTICO ====================
print_step "DIAGNÓSTICO DEL SISTEMA"

# Verificar arquitectura
ARCH=$(uname -m)
print_info "Arquitectura: $ARCH"

# Verificar memoria RAM
MEM_TOTAL=$(free -m | awk '/^Mem:/{print $2}')
print_info "Memoria RAM total: ${MEM_TOTAL}MB"

if [ $MEM_TOTAL -lt 512 ]; then
    print_warning "Poca memoria RAM detectable. Puede causar problemas."
fi

# Verificar espacio en disco
DISK_SPACE=$(df -m /opt | awk 'NR==2 {print $4}' 2>/dev/null || df -m / | awk 'NR==2 {print $4}')
print_info "Espacio disponible: ${DISK_SPACE}MB"

if [ $DISK_SPACE -lt 1000 ]; then
    print_warning "Poco espacio en disco. Se recomienda al menos 1GB."
fi

# Verificar conectividad a Internet
print_info "Verificando conectividad..."
if ping -c 1 google.com &> /dev/null; then
    print_success "Conexión a Internet detectada"
else
    print_error "Sin conexión a Internet. Verifica tu red."
    exit 1
fi

# ==================== ACTUALIZAR SISTEMA ====================
print_step "ACTUALIZANDO SISTEMA"
apt-get update -qq && print_success "Repositorios actualizados"
apt-get upgrade -y -qq && print_success "Paquetes actualizados"

# ==================== INSTALAR DEPENDENCIAS ====================
print_step "INSTALANDO DEPENDENCIAS DEL SISTEMA"

# Lista completa de dependencias
DEPS="curl wget git build-essential libnss3 libatk-bridge2.0-0 libx11-xcb1 libxcb-dri3-0 libdrm2 libgbm1 libxcomposite1 libxdamage1 libxrandr2 libasound2 libpangocairo-1.0-0 libxcursor1 libxi6 libxtst6 libcups2 libxss1 libxshmfence1 fonts-liberation libappindicator3-1 libatspi2.0-0 libnspr4 libgtk-3-0 ca-certificates xdg-utils"

apt-get install -y -qq $DEPS && print_success "Dependencias instaladas"

# ==================== INSTALAR CHROMIUM ====================
print_step "INSTALANDO CHROMIUM"

if command -v chromium-browser &> /dev/null; then
    print_success "Chromium ya está instalado"
else
    apt-get install -y -qq chromium-browser chromium-codecs-ffmpeg && print_success "Chromium instalado"
fi

CHROME_PATH=$(which chromium-browser 2>/dev/null || echo "/usr/bin/chromium-browser")
print_info "Chromium: $CHROME_PATH"

# ==================== INSTALAR NODE.JS 18 ====================
print_step "INSTALANDO NODE.JS 18"

if command -v node &> /dev/null; then
    NODE_VER=$(node -v)
    print_info "Node.js ya instalado: $NODE_VER"
else
    curl -fsSL https://deb.nodesource.com/setup_18.x | bash - &> /dev/null
    apt-get install -y -qq nodejs && print_success "Node.js 18 instalado"
fi

# ==================== CONFIGURAR TIMEZONE RD ====================
print_step "CONFIGURANDO ZONA HORARIA"

timedatectl set-timezone America/Santo_Domingo 2>/dev/null || echo "America/Santo_Domingo" > /etc/timezone
export TZ='America/Santo_Domingo'
print_success "Zona horaria: America/Santo_Domingo (RD)"

# ==================== CREAR ESTRUCTURA DE DIRECTORIOS ====================
print_step "CREANDO ESTRUCTURA DE DIRECTORIOS"

INSTALL_DIR="/opt/gzmbot"
mkdir -p $INSTALL_DIR/views
mkdir -p $INSTALL_DIR/data
mkdir -p $INSTALL_DIR/media
mkdir -p $INSTALL_DIR/backups
mkdir -p $INSTALL_DIR/.wwebjs_auth
mkdir -p $INSTALL_DIR/.cache/puppeteer
cd $INSTALL_DIR

print_success "Directorios creados en $INSTALL_DIR"

# ==================== CONFIG.JSON ====================
print_step "GENERANDO ARCHIVOS DE CONFIGURACIÓN"

cat <<EOF > config.json
{
  "adminUser": "$ADMIN_USER",
  "adminPassword": "$ADMIN_PASS",
  "port": 80,
  "sessionSecret": "$(openssl rand -hex 24)",
  "backupPhone": ""
}
EOF

print_success "config.json creado"

# ==================== APP.JS (BACKEND MEJORADO) ====================
print_step "CREANDO APP.JS"

cat <<'APPEOF' > app.js
// Forzar timezone del proceso a RD
process.env.TZ = 'America/Santo_Domingo';

// Configuración de Puppeteer para entornos headless
process.env.PUPPETEER_SKIP_CHROMIUM_DOWNLOAD = 'false';
process.env.PUPPETEER_EXECUTABLE_PATH = '/usr/bin/chromium-browser';

const { Client, LocalAuth, MessageMedia } = require('whatsapp-web.js');
const qrcode = require('qrcode');
const express = require('express');
const http = require('http');
const socketIo = require('socket.io');
const session = require('express-session');
const fs = require('fs');
const path = require('path');
const cron = require('node-cron');
const moment = require('moment-timezone');
const multer = require('multer');
const { exec } = require('child_process');

const TZ = 'America/Santo_Domingo';
const app = express();
const server = http.createServer(app);
const io = socketIo(server, {
    cors: {
        origin: "*",
        methods: ["GET", "POST"]
    }
});

const DB_PATH = path.join(__dirname, 'data/database.json');
const CONFIG_PATH = path.join(__dirname, 'config.json');
const MEDIA_PATH = path.join(__dirname, 'media');
const BACKUP_PATH = path.join(__dirname, 'backups');
const AUTH_PATH = path.join(__dirname, '.wwebjs_auth');
const CHROME_PATH = '/usr/bin/chromium-browser';

// Verificar existencia de Chromium
if (!fs.existsSync(CHROME_PATH)) {
    console.log('⚠️ Chromium no encontrado en la ruta predeterminada, buscando...');
    // Intentar encontrar chromium en otras ubicaciones comunes
    const possiblePaths = [
        '/usr/bin/chromium',
        '/usr/bin/chromium-browser',
        '/snap/bin/chromium'
    ];
    
    for (const p of possiblePaths) {
        if (fs.existsSync(p)) {
            process.env.PUPPETEER_EXECUTABLE_PATH = p;
            console.log(`✅ Chromium encontrado en: ${p}`);
            break;
        }
    }
}

// Inicializar DB si no existe
if (!fs.existsSync(DB_PATH)) {
    fs.writeFileSync(DB_PATH, JSON.stringify({
        training: [], reminders: [], excluded: [], learning: [],
        stats: { replied: 0, total: 0 }
    }));
}

const storage = multer.diskStorage({
    destination: (req, file, cb) => {
        cb(null, file.fieldname === 'backup' ? BACKUP_PATH : MEDIA_PATH);
    },
    filename: (req, file, cb) => cb(null, Date.now() + '-' + file.originalname)
});
const upload = multer({ storage });

app.use(express.json());
app.use(express.urlencoded({ extended: true }));
app.use('/media', express.static(MEDIA_PATH));

const getConfig = () => JSON.parse(fs.readFileSync(CONFIG_PATH));
let config = getConfig();

app.use(session({
    secret: config.sessionSecret,
    resave: false,
    saveUninitialized: true,
    cookie: { maxAge: 86400000 }
}));

const getDB = () => JSON.parse(fs.readFileSync(DB_PATH));
const saveDB = (data) => fs.writeFileSync(DB_PATH, JSON.stringify(data, null, 2));

function nowRD() {
    return moment().tz(TZ);
}

let client;
let botStatus = "Desconectado";
let lastQR = null;
let isConnected = false;
let qrGenerationAttempts = 0;
let clientInitialized = false;

console.log('🕐 Hora del servidor:', new Date().toString());
console.log('🕐 Hora RD (moment):', nowRD().format('DD/MM/YYYY HH:mm:ss'));
console.log('🕐 Timezone configurado:', TZ);
console.log('🖥️  Chromium path:', process.env.PUPPETEER_EXECUTABLE_PATH || CHROME_PATH);

// Función para limpiar sesión
function cleanAuthSession() {
    console.log('🧹 Limpiando sesión anterior...');
    if (fs.existsSync(AUTH_PATH)) {
        try {
            fs.rmSync(AUTH_PATH, { recursive: true, force: true });
            console.log('✅ Sesión eliminada');
        } catch (e) {
            console.error('❌ Error eliminando sesión:', e.message);
        }
    }
    
    // Limpiar también la caché de Puppeteer
    const puppeteerCache = path.join(__dirname, '.cache');
    if (fs.existsSync(puppeteerCache)) {
        try {
            fs.rmSync(puppeteerCache, { recursive: true, force: true });
            console.log('✅ Caché de Puppeteer eliminada');
        } catch (e) {
            console.error('❌ Error eliminando caché:', e.message);
        }
    }
}

// Verificar conectividad a Internet
function checkInternet() {
    return new Promise((resolve) => {
        exec('ping -c 1 google.com', (error) => {
            resolve(!error);
        });
    });
}

// Inicializar bot con configuración ultra-robusta
async function initBot() {
    if (clientInitialized) {
        console.log('⚠️ Cliente ya inicializado, cerrando anterior...');
        try {
            await client.destroy();
        } catch (e) {
            console.error('Error destruyendo cliente anterior:', e.message);
        }
    }
    
    // Verificar internet
    const hasInternet = await checkInternet();
    if (!hasInternet) {
        console.error('❌ Sin conexión a Internet. Verifica tu conexión.');
        botStatus = "Sin Internet";
        io.emit('status_update', botStatus);
        setTimeout(initBot, 30000); // Reintentar en 30 segundos
        return;
    }
    
    console.log('🔄 Inicializando cliente de WhatsApp...');
    
    // Limpiar si hay muchos intentos fallidos
    if (qrGenerationAttempts > 3) {
        cleanAuthSession();
        qrGenerationAttempts = 0;
    }
    
    const puppeteerConfig = {
        headless: true,
        args: [
            '--no-sandbox',
            '--disable-setuid-sandbox',
            '--disable-dev-shm-usage',
            '--disable-accelerated-2d-canvas',
            '--disable-gpu',
            '--disable-software-rasterizer',
            '--disable-features=VizDisplayCompositor',
            '--disable-features=IsolateOrigins,site-per-process',
            '--disable-web-security',
            '--disable-features=BlockInsecurePrivateNetworkRequests',
            '--disable-features=OutOfBlinkCors',
            '--disable-webgl',
            '--disable-font-subpixel-positioning',
            '--disable-lcd-text',
            '--disable-default-apps',
            '--disable-extensions',
            '--disable-component-extensions-with-background-pages',
            '--disable-background-timer-throttling',
            '--disable-backgrounding-occluded-windows',
            '--disable-renderer-backgrounding',
            '--window-size=1920,1080',
            '--start-maximized',
            '--no-first-run',
            '--no-default-browser-check',
            '--disable-client-side-phishing-detection',
            '--disable-component-update',
            '--disable-sync',
            '--disable-breakpad',
            '--disable-ipc-flooding-protection',
            '--disable-background-networking',
            '--metrics-recording-only',
            '--mute-audio'
        ]
    };
    
    // Usar el executable path si está disponible
    if (process.env.PUPPETEER_EXECUTABLE_PATH) {
        puppeteerConfig.executablePath = process.env.PUPPETEER_EXECUTABLE_PATH;
    }
    
    client = new Client({
        authStrategy: new LocalAuth({ 
            dataPath: AUTH_PATH,
            clientId: 'gzmbot-main-client' 
        }),
        puppeteer: puppeteerConfig,
        webVersionCache: {
            type: 'remote',
            remotePath: 'https://raw.githubusercontent.com/wppconnect-team/wa-version/main/html/2.2412.54.html',
        }
    });

    client.on('qr', (qr) => {
        console.log('📲 QR generado correctamente');
        botStatus = "Esperando QR";
        isConnected = false;
        lastQR = qr;
        qrcode.toDataURL(qr, (err, url) => {
            if (err) {
                console.error('❌ Error generando imagen QR:', err);
                return;
            }
            io.emit('qr_update', url);
            io.emit('connection_status', { connected: false, status: botStatus });
            io.emit('status_update', botStatus);
            console.log('✅ QR enviado al cliente web');
        });
        qrGenerationAttempts++;
    });

    client.on('ready', () => {
        botStatus = "Conectado";
        isConnected = true;
        lastQR = null;
        qrGenerationAttempts = 0;
        clientInitialized = true;
        io.emit('status_update', botStatus);
        io.emit('connection_status', { connected: true, status: botStatus });
        console.log('✅✅✅ BOT CONECTADO EXITOSAMENTE -', nowRD().format('DD/MM/YYYY HH:mm:ss'));
    });

    client.on('authenticated', () => {
        console.log('🔐 Autenticación exitosa');
    });

    client.on('auth_failure', (msg) => {
        console.error('❌ Fallo de autenticación:', msg);
        botStatus = "Error de autenticación";
        io.emit('status_update', botStatus);
        qrGenerationAttempts++;
        
        if (qrGenerationAttempts > 5) {
            console.log('🔄 Demasiados fallos, limpiando sesión...');
            cleanAuthSession();
            qrGenerationAttempts = 0;
        }
    });

    client.on('disconnected', (reason) => {
        botStatus = "Desconectado";
        isConnected = false;
        clientInitialized = false;
        io.emit('status_update', botStatus);
        io.emit('connection_status', { connected: false, status: botStatus });
        console.log('❌ Bot desconectado:', reason);
        
        // Reintentar conexión después de 10 segundos
        setTimeout(() => {
            if (!isConnected) {
                console.log('🔄 Reintentando conexión...');
                initBot();
            }
        }, 10000);
    });

    client.on('message', async (msg) => {
        try {
            if (msg.from === 'status@broadcast') return;

            const db = getDB();
            const phone = msg.from.replace('@c.us', '');

            if (db.excluded.some(ex => phone.includes(ex.phone))) return;

            const text = msg.body.toLowerCase().trim();

            const trigger = db.training.find(t => {
                const key = t.key.toLowerCase().trim();
                return text.includes(key) || key.includes(text);
            });

            if (trigger) {
                if (trigger.mediaPaths && trigger.mediaPaths.length > 0) {
                    try {
                        const firstMedia = MessageMedia.fromFilePath(trigger.mediaPaths[0]);
                        await msg.reply(firstMedia, null, { caption: trigger.response });
                        for (let i = 1; i < trigger.mediaPaths.length; i++) {
                            const media = MessageMedia.fromFilePath(trigger.mediaPaths[i]);
                            await msg.reply(media);
                        }
                    } catch (e) {
                        await msg.reply(trigger.response);
                    }
                } else {
                    await msg.reply(trigger.response);
                }
                db.stats.replied++;
            } else if (!msg.from.includes('@g.us')) {
                const msgData = {
                    text: msg.body, from: phone,
                    date: nowRD().format('DD/MM HH:mm'),
                    hasMedia: msg.hasMedia, type: msg.type
                };
                if (!db.learning.some(l => l.text === msg.body && l.from === phone)) {
                    db.learning.push(msgData);
                }
            }

            db.stats.total++;
            saveDB(db);
            io.emit('data_update', db);
        } catch (e) {
            console.error('Error en mensaje:', e);
        }
    });

    try {
        console.log('🚀 Iniciando cliente...');
        await client.initialize();
        console.log('✅ Cliente inicializado correctamente');
    } catch (e) {
        console.error('❌ Error al iniciar cliente:', e);
        botStatus = "Error de inicialización";
        io.emit('status_update', botStatus);
        
        // Reintentar después de 15 segundos
        setTimeout(initBot, 15000);
    }
}

async function createBackup() {
    try {
        const timestamp = nowRD().format('YYYY-MM-DD_HH-mm-ss');
        const backupData = {
            date: nowRD().format('DD/MM/YYYY HH:mm'),
            database: getDB(),
            config: getConfig()
        };
        const backupFile = path.join(BACKUP_PATH, 'backup_' + timestamp + '.json');
        fs.writeFileSync(backupFile, JSON.stringify(backupData, null, 2));
        console.log('✅ Backup creado:', backupFile, '-', nowRD().format('DD/MM/YYYY HH:mm:ss'));
        return backupFile;
    } catch (e) {
        console.error('❌ Error backup:', e);
        return null;
    }
}

async function sendBackupToWhatsApp(backupFile) {
    if (!isConnected) {
        console.log('❌ Bot no conectado, backup no enviado');
        return false;
    }
    const freshConfig = getConfig();
    if (!freshConfig.backupPhone || freshConfig.backupPhone.trim() === '') {
        console.log('❌ No hay número de backup configurado');
        return false;
    }
    try {
        const chatId = freshConfig.backupPhone.includes('@') ?
            freshConfig.backupPhone : freshConfig.backupPhone + '@c.us';
        const media = MessageMedia.fromFilePath(backupFile);
        await client.sendMessage(chatId, media, {
            caption: '🔐 *Backup GZMBOT*\n\n📅 Fecha: ' + nowRD().format('DD/MM/YYYY HH:mm') + '\n🕐 Hora RD\n\n✅ Copia de seguridad completada'
        });
        console.log('✅ Backup enviado a WhatsApp -', nowRD().format('HH:mm:ss'));
        return true;
    } catch (e) {
        console.error('❌ Error enviando backup:', e);
        return false;
    }
}

// ============ CRON BACKUP AUTOMÁTICO 12:00 AM HORA RD ============
cron.schedule('0 0 * * *', async () => {
    console.log('🔄 [CRON] Backup automático iniciado -', nowRD().format('DD/MM/YYYY HH:mm:ss'));
    const bf = await createBackup();
    if (bf) {
        const sent = await sendBackupToWhatsApp(bf);
        console.log('🔄 [CRON] Backup enviado:', sent);
    }
}, {
    scheduled: true,
    timezone: TZ
});

console.log('📅 Backup automático programado para 12:00 AM hora RD');

// ============ CRON RECORDATORIOS - CADA MINUTO ============
cron.schedule('* * * * *', () => {
    if (!isConnected) return;

    const db = getDB();
    const currentRD = nowRD().format('YYYY-MM-DDTHH:mm');
    console.log(`⏰ [CRON] Verificando recordatorios a las ${currentRD}`); // Log de depuración
    let changed = false;

    for (let i = db.reminders.length - 1; i >= 0; i--) {
        const rem = db.reminders[i];

        if (rem.date === currentRD) {
            console.log(`🔔 Enviando recordatorio a ${rem.name} (${rem.phone}) - ${currentRD}`);

            const chatId = rem.phone.includes('@') ? rem.phone : rem.phone + '@c.us';
            client.sendMessage(chatId, rem.message) // El mensaje conserva saltos de línea
                .then(() => console.log(`✅ Recordatorio enviado a ${rem.name}`))
                .catch(e => console.error("❌ Error recordatorio:", e.message));

            if (rem.freq === 'Diario') {
                rem.date = moment.tz(rem.date, TZ).add(1, 'days').format('YYYY-MM-DDTHH:mm');
                console.log(`   🔄 Nueva fecha (diario): ${rem.date}`);
            } else if (rem.freq === 'Semanal') {
                rem.date = moment.tz(rem.date, TZ).add(7, 'days').format('YYYY-MM-DDTHH:mm');
                console.log(`   🔄 Nueva fecha (semanal): ${rem.date}`);
            } else if (rem.freq === 'Mensual') {
                rem.date = moment.tz(rem.date, TZ).add(1, 'months').format('YYYY-MM-DDTHH:mm');
                console.log(`   🔄 Nueva fecha (mensual): ${rem.date}`);
            } else if (rem.freq === 'Anual') {
                rem.date = moment.tz(rem.date, TZ).add(1, 'years').format('YYYY-MM-DDTHH:mm');
                console.log(`   🔄 Nueva fecha (anual): ${rem.date}`);
            } else {
                db.reminders.splice(i, 1);
                console.log(`   🗑️ Recordatorio único eliminado`);
            }
            changed = true;
        }
    }

    if (changed) {
        saveDB(db);
        io.emit('data_update', db);
    }
}, {
    scheduled: true,
    timezone: TZ
});

console.log('⏰ Recordatorios activos - verificando cada minuto en hora RD');

// Iniciar el bot después de 2 segundos (para asegurar que todo esté listo)
setTimeout(initBot, 2000);

const checkAuth = (req, res, next) => req.session.user ? next() : res.status(401).send("Unauthorized");

app.get('/', (req, res) => req.session.user ? res.sendFile(path.join(__dirname, 'views/index.html')) : res.redirect('/login'));
app.get('/login', (req, res) => res.sendFile(path.join(__dirname, 'views/login.html')));

app.post('/login', (req, res) => {
    const fc = getConfig();
    if (req.body.user === fc.adminUser && req.body.pass === fc.adminPassword) {
        req.session.user = req.body.user;
        res.json({ ok: true });
    } else res.json({ ok: false });
});

app.get('/api/data', checkAuth, (req, res) => {
    res.json({
        ...getDB(), 
        botStatus, 
        qr: lastQR, 
        isConnected,
        backupPhone: getConfig().backupPhone || '',
        serverTime: nowRD().format('DD/MM/YYYY HH:mm:ss'),
        timezone: TZ,
        chromePath: process.env.PUPPETEER_EXECUTABLE_PATH || 'No encontrado'
    });
});

app.get('/api/server-time', checkAuth, (req, res) => {
    res.json({
        serverTimeRD: nowRD().format('DD/MM/YYYY HH:mm:ss'),
        serverTimeUTC: moment.utc().format('DD/MM/YYYY HH:mm:ss'),
        timezone: TZ,
        nextBackup: '12:00 AM hora RD'
    });
});

app.post('/api/train', checkAuth, upload.array('media', 10), (req, res) => {
    const db = getDB();
    const { id, key, response } = req.body;
    const trainData = {
        key, response,
        mediaPaths: req.files && req.files.length > 0 ? req.files.map(f => f.path) : [],
        mediaTypes: req.files && req.files.length > 0 ? req.files.map(f => f.mimetype) : []
    };
    if (id !== "" && id !== null && id !== undefined && id !== "undefined") {
        if (db.training[id] && db.training[id].mediaPaths && db.training[id].mediaPaths.length > 0) {
            db.training[id].mediaPaths.forEach(p => { if (fs.existsSync(p)) fs.unlinkSync(p); });
        }
        db.training[id] = trainData;
    } else {
        db.training.push(trainData);
    }
    saveDB(db); io.emit('data_update', db); res.json({ ok: true });
});

app.delete('/api/train/:id', checkAuth, (req, res) => {
    const db = getDB();
    const item = db.training[req.params.id];
    if (item && item.mediaPaths && item.mediaPaths.length > 0) {
        item.mediaPaths.forEach(p => { if (fs.existsSync(p)) fs.unlinkSync(p); });
    }
    db.training.splice(req.params.id, 1);
    saveDB(db); io.emit('data_update', db); res.json({ ok: true });
});

app.get('/api/train/template', checkAuth, (req, res) => {
    const template = '# PLANTILLA DE ENTRENAMIENTO GZMBOT\n# =====================================\n#\n# FORMATO:\n# PREGUNTA: texto que el usuario escribe\n# RESPUESTA: texto que el bot responde\n# ---\n\nPREGUNTA: hola\nRESPUESTA: ¡Hola! Bienvenido. ¿En qué puedo ayudarte?\n---\n\nPREGUNTA: horario\nRESPUESTA: Lunes a Viernes: 9:00 AM - 6:00 PM\\nSábados: 9:00 AM - 1:00 PM\\nDomingos: Cerrado\n---\n\nPREGUNTA: precio\nRESPUESTA: Contacta a nuestro equipo de ventas para precios.\n---\n\nPREGUNTA: ubicación\nRESPUESTA: Av. Principal #123, Ciudad.\n---\n';
    res.setHeader('Content-Type', 'text/plain; charset=utf-8');
    res.setHeader('Content-Disposition', 'attachment; filename=plantilla_entrenamiento.txt');
    res.send(template);
});

app.post('/api/train/import', checkAuth, upload.single('file'), (req, res) => {
    try {
        const fileContent = fs.readFileSync(req.file.path, 'utf-8');
        const lines = fileContent.split('\n');
        const db = getDB();
        let cQ = '', cR = '', imported = 0;
        for (let line of lines) {
            line = line.trim();
            if (line.startsWith('#') || line === '') continue;
            if (line.startsWith('PREGUNTA:')) cQ = line.replace('PREGUNTA:', '').trim();
            else if (line.startsWith('RESPUESTA:')) {
                cR = line.replace('RESPUESTA:', '').trim().replace(/\\n/g, '\n');
            } else if (line === '---' && cQ && cR) {
                db.training.push({ key: cQ, response: cR, mediaPaths: [], mediaTypes: [] });
                imported++; cQ = ''; cR = '';
            }
        }
        if (cQ && cR) { db.training.push({ key: cQ, response: cR, mediaPaths: [], mediaTypes: [] }); imported++; }
        saveDB(db); io.emit('data_update', db); fs.unlinkSync(req.file.path);
        res.json({ ok: true, imported });
    } catch (e) { res.status(500).json({ ok: false, error: e.message }); }
});

app.get('/api/train/export', checkAuth, (req, res) => {
    const db = getDB();
    let content = '# RESPUESTAS GZMBOT\n# Exportado: ' + nowRD().format('DD/MM/YYYY HH:mm') + '\n# Total: ' + db.training.length + '\n\n';
    db.training.forEach(t => {
        if (!t.mediaPaths || t.mediaPaths.length === 0) {
            content += 'PREGUNTA: ' + t.key + '\nRESPUESTA: ' + t.response.replace(/\n/g, '\\n') + '\n---\n\n';
        }
    });
    res.setHeader('Content-Type', 'text/plain; charset=utf-8');
    res.setHeader('Content-Disposition', 'attachment; filename=respuestas_exportadas.txt');
    res.send(content);
});

app.post('/api/reminders', checkAuth, (req, res) => {
    const db = getDB();
    const { id, name, phone, message, freq, date } = req.body;
    const data = { name, phone: phone.replace(/\D/g, ''), message, freq, date };

    console.log('📝 Recordatorio guardado:', name, '- Fecha:', date, '- Hora actual RD:', nowRD().format('YYYY-MM-DDTHH:mm'));

    // Convertir id a número si es posible para asegurar que se use como índice
    const idx = id && id !== "" && id !== null && id !== undefined && id !== "undefined" ? Number(id) : -1;
    if (idx >= 0 && idx < db.reminders.length) {
        db.reminders[idx] = data;
    } else {
        db.reminders.push(data);
    }
    saveDB(db); io.emit('data_update', db); res.json({ ok: true });
});

app.delete('/api/reminders/:id', checkAuth, (req, res) => {
    const db = getDB(); db.reminders.splice(req.params.id, 1);
    saveDB(db); io.emit('data_update', db); res.json({ ok: true });
});

app.post('/api/exclude', checkAuth, (req, res) => {
    const db = getDB(); db.excluded.push(req.body);
    saveDB(db); io.emit('data_update', db); res.json({ ok: true });
});

app.delete('/api/exclude/:id', checkAuth, (req, res) => {
    const db = getDB(); db.excluded.splice(req.params.id, 1);
    saveDB(db); io.emit('data_update', db); res.json({ ok: true });
});

app.delete('/api/learning/:id', checkAuth, (req, res) => {
    const db = getDB(); db.learning.splice(req.params.id, 1);
    saveDB(db); io.emit('data_update', db); res.json({ ok: true });
});

app.post('/api/config/credentials', checkAuth, (req, res) => {
    const fc = getConfig();
    if (req.body.user) fc.adminUser = req.body.user;
    if (req.body.pass) fc.adminPassword = req.body.pass;
    fs.writeFileSync(CONFIG_PATH, JSON.stringify(fc, null, 2));
    res.json({ ok: true });
});

app.post('/api/config/backup-phone', checkAuth, (req, res) => {
    const fc = getConfig();
    fc.backupPhone = req.body.backupPhone || '';
    fs.writeFileSync(CONFIG_PATH, JSON.stringify(fc, null, 2));
    console.log('📱 Número backup guardado:', fc.backupPhone);
    res.json({ ok: true });
});

app.get('/api/backup/download', checkAuth, async (req, res) => {
    try {
        const bf = await createBackup();
        if (bf) {
            res.download(bf, path.basename(bf), (err) => {
                if (err && !res.headersSent) res.status(500).send('Error');
            });
        } else res.status(500).json({ ok: false, message: 'Error creando backup' });
    } catch (e) { res.status(500).json({ ok: false, error: e.message }); }
});

app.post('/api/backup/send', checkAuth, async (req, res) => {
    if (!isConnected) return res.json({ ok: false, message: 'Bot no está conectado' });
    const fc = getConfig();
    if (!fc.backupPhone || fc.backupPhone.trim() === '') return res.json({ ok: false, message: 'No hay número configurado. Guárdalo primero.' });
    const bf = await createBackup();
    if (!bf) return res.json({ ok: false, message: 'Error creando backup' });
    const sent = await sendBackupToWhatsApp(bf);
    res.json({ ok: sent, message: sent ? 'Backup enviado correctamente' : 'Error enviando backup' });
});

app.post('/api/backup/restore', checkAuth, upload.single('backup'), (req, res) => {
    try {
        const bc = JSON.parse(fs.readFileSync(req.file.path, 'utf-8'));
        if (bc.database) { saveDB(bc.database); io.emit('data_update', bc.database); }
        if (bc.config) {
            const cc = getConfig();
            const nc = { ...bc.config, adminUser: cc.adminUser, adminPassword: cc.adminPassword, sessionSecret: cc.sessionSecret };
            fs.writeFileSync(CONFIG_PATH, JSON.stringify(nc, null, 2));
        }
        fs.unlinkSync(req.file.path);
        res.json({ ok: true });
    } catch (e) { res.status(500).json({ ok: false, error: e.message }); }
});

app.post('/api/logout-wa', checkAuth, async (req, res) => {
    try {
        await client.logout();
        if (fs.existsSync(AUTH_PATH)) fs.rmSync(AUTH_PATH, { recursive: true, force: true });
        isConnected = false;
        botStatus = "Desconectado";
        clientInitialized = false;
        const db = getDB();
        db.stats.replied = 0;
        db.stats.total = 0;
        saveDB(db);
        io.emit('data_update', db);
        res.json({ ok: true });
        setTimeout(() => process.exit(0), 1000);
    } catch (e) { res.status(500).send(e.message); }
});

server.listen(config.port, '0.0.0.0', () => {
    console.log('🚀 GZMBOT ONLINE en puerto', config.port);
    console.log('🕐 Hora actual RD:', nowRD().format('DD/MM/YYYY HH:mm:ss'));
    console.log('📅 Próximo backup: 12:00 AM hora RD');
    console.log('📱 Panel web disponible en http://localhost:' + config.port);
});

// Manejar cierre graceful
process.on('SIGINT', async () => {
    console.log('🛑 Cerrando aplicación...');
    if (client) {
        try {
            await client.destroy();
            console.log('✅ Cliente de WhatsApp cerrado');
        } catch (e) {
            console.error('Error cerrando cliente:', e.message);
        }
    }
    process.exit(0);
});
APPEOF

print_success "app.js creado"

# ==================== INDEX.HTML (MODERNO CON CORRECCIONES) ====================
print_step "CREANDO INTERFAZ WEB"

cat <<'HTMLEOF' > views/index.html
<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
    <title>GZMBOT | Enterprise</title>
    <script src="https://cdn.tailwindcss.com"></script>
    <script src="/socket.io/socket.io.js"></script>
    <script src="https://unpkg.com/lucide@latest"></script>
    <link href="https://fonts.googleapis.com/css2?family=Plus+Jakarta+Sans:wght@400;500;600;700;800&display=swap" rel="stylesheet">
    <style>
        * { box-sizing: border-box; margin: 0; padding: 0; }
        body { background: #0a0a0f; color: #ffffff; font-family: 'Plus Jakarta Sans', sans-serif; }
        .glass { background: rgba(20, 20, 30, 0.7); backdrop-filter: blur(16px); border: 1px solid rgba(255,255,255,0.05); border-radius: 24px; box-shadow: 0 20px 40px -15px rgba(0,0,0,0.5); }
        .glass-card { background: rgba(25, 25, 35, 0.8); border: 1px solid rgba(255,255,255,0.03); border-radius: 20px; transition: all 0.2s ease; }
        .glass-card:hover { border-color: rgba(37, 99, 235, 0.3); transform: translateY(-2px); box-shadow: 0 20px 30px -10px rgba(37,99,235,0.2); }
        .sidebar-item { display: flex; align-items: center; gap: 14px; padding: 14px 18px; border-radius: 18px; color: #a1a1aa; transition: all 0.3s; cursor: pointer; font-weight: 500; }
        .sidebar-item:hover { background: rgba(255,255,255,0.05); color: #fff; }
        .sidebar-item.active { background: linear-gradient(135deg, #2563eb 0%, #1e40af 100%); color: #fff; box-shadow: 0 10px 20px -5px rgba(37, 99, 235, 0.5); }
        .page { display: none; animation: fadeIn 0.3s ease-out; }
        .page.active { display: block; }
        @keyframes fadeIn { from { opacity: 0; transform: translateY(10px); } to { opacity: 1; transform: translateY(0); } }
        input, select, textarea {
            background: #1a1a24 !important; border: 1px solid #2a2a35 !important;
            color: #fff !important; padding: 12px 16px !important; border-radius: 16px !important;
            outline: none; width: 100%; font-size: 15px; transition: border 0.2s;
        }
        input:focus, textarea:focus { border-color: #2563eb !important; }
        ::-webkit-scrollbar { width: 6px; }
        ::-webkit-scrollbar-thumb { background: #2a2a35; border-radius: 10px; }
        .media-preview { max-width: 100px; max-height: 100px; border-radius: 12px; margin: 4px; object-fit: cover; border: 2px solid #2a2a35; }
        .media-type-selector { display: flex; gap: 8px; margin-bottom: 12px; flex-wrap: wrap; }
        .media-type-btn { padding: 10px 18px; background: #1a1a24; border: 1px solid #2a2a35; border-radius: 30px; cursor: pointer; transition: all 0.3s; color: #a1a1aa; font-weight: 500; display: flex; align-items: center; gap: 6px; }
        .media-type-btn.active { background: #2563eb; border-color: #2563eb; color: #fff; }
        .media-preview-container { display: flex; flex-wrap: wrap; gap: 10px; margin-top: 10px; }
        .media-item { position: relative; }
        .media-remove { position: absolute; top: -6px; right: -6px; background: #ef4444; color: white; border-radius: 50%; width: 22px; height: 22px; display: flex; align-items: center; justify-content: center; cursor: pointer; font-size: 14px; font-weight: bold; border: 2px solid #1a1a24; }
        .btn { padding: 12px 24px; border-radius: 30px; font-weight: 600; transition: all 0.2s; display: inline-flex; align-items: center; gap: 8px; justify-content: center; }
        .btn-primary { background: #2563eb; color: #fff; box-shadow: 0 8px 16px -4px rgba(37,99,235,0.3); }
        .btn-primary:hover { background: #1e4fcf; transform: translateY(-2px); }
        .btn-success { background: #10b981; color: #fff; box-shadow: 0 8px 16px -4px rgba(16,185,129,0.3); }
        .btn-success:hover { background: #0ea271; transform: translateY(-2px); }
        .btn-danger { background: #ef4444; color: #fff; box-shadow: 0 8px 16px -4px rgba(239,68,68,0.3); }
        .btn-danger:hover { background: #dc2626; transform: translateY(-2px); }
        .btn-warning { background: #f59e0b; color: #fff; box-shadow: 0 8px 16px -4px rgba(245,158,11,0.3); }
        .btn-warning:hover { background: #d97706; transform: translateY(-2px); }
        .btn-outline { background: transparent; border: 1px solid #2a2a35; color: #a1a1aa; }
        .btn-outline:hover { border-color: #2563eb; color: #fff; }
        /* Clase para preservar saltos de línea en mensajes */
        .preserve-lines { white-space: pre-wrap; }
    </style>
</head>
<body class="flex h-screen overflow-hidden">

    <aside id="sidebar" class="fixed inset-y-0 left-0 z-50 w-72 glass border-r border-white/5 -translate-x-full lg:translate-x-0 lg:static transition-transform duration-300 flex flex-col p-6 overflow-y-auto">
        <div class="flex items-center gap-3 mb-10 px-2">
            <div class="w-10 h-10 bg-gradient-to-br from-blue-600 to-blue-800 rounded-xl flex items-center justify-center shadow-lg flex-shrink-0">
                <i data-lucide="bot" class="text-white w-6 h-6"></i>
            </div>
            <span class="text-2xl font-extrabold tracking-tighter bg-gradient-to-r from-white to-zinc-400 bg-clip-text text-transparent">GZMBOT</span>
        </div>
        <nav class="space-y-1 flex-1">
            <div onclick="nav('dash')" id="n-dash" class="sidebar-item active"><i data-lucide="layout-grid" class="w-5 h-5"></i><span>Dashboard</span></div>
            <div onclick="nav('conn')" id="n-conn" class="sidebar-item"><i data-lucide="qr-code" class="w-5 h-5"></i><span>Conexión</span></div>
            <div onclick="nav('train')" id="n-train" class="sidebar-item"><i data-lucide="message-square" class="w-5 h-5"></i><span>Respuestas</span></div>
            <div onclick="nav('learn')" id="n-learn" class="sidebar-item"><i data-lucide="brain" class="w-5 h-5"></i><span>Aprender</span></div>
            <div onclick="nav('rem')" id="n-rem" class="sidebar-item"><i data-lucide="bell" class="w-5 h-5"></i><span>Recordatorios</span></div>
            <div onclick="nav('excl')" id="n-excl" class="sidebar-item"><i data-lucide="shield-off" class="w-5 h-5"></i><span>Excluidos</span></div>
            <div onclick="nav('config')" id="n-config" class="sidebar-item"><i data-lucide="settings" class="w-5 h-5"></i><span>Ajustes</span></div>
        </nav>
        <button onclick="location.href='/login'" class="sidebar-item text-red-400 hover:bg-red-500/10 hover:text-red-400 mt-auto">
            <i data-lucide="power" class="w-5 h-5"></i><span>Salir del Panel</span>
        </button>
    </aside>

    <main class="flex-1 flex flex-col min-w-0 overflow-hidden bg-[#0a0a0f]">
        <header class="lg:hidden p-4 glass flex justify-between items-center flex-shrink-0 mx-4 mt-4 rounded-2xl">
            <span class="font-bold text-lg">GZMBOT</span>
            <button onclick="toggleSidebar()" class="p-2 hover:bg-white/10 rounded-xl transition"><i data-lucide="menu"></i></button>
        </header>

        <div class="flex-1 overflow-y-auto p-4 sm:p-6 lg:p-8">

            <!-- DASHBOARD -->
            <div id="p-dash" class="page active">
                <div class="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-4 mb-8">
                    <h1 class="text-3xl sm:text-4xl font-extrabold tracking-tight">Dashboard</h1>
                    <div class="flex items-center gap-4">
                        <div id="server-clock" class="text-sm text-zinc-500 font-mono bg-white/5 px-4 py-2 rounded-full"></div>
                        <div class="px-4 py-2 glass rounded-full flex items-center gap-2">
                            <div id="dot" class="w-2.5 h-2.5 rounded-full bg-red-500 animate-pulse"></div>
                            <span id="bot-status" class="text-xs font-bold uppercase tracking-widest text-zinc-400">Desconectado</span>
                        </div>
                    </div>
                </div>
                <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
                    <div class="glass-card p-8">
                        <div class="flex items-center gap-4 mb-4">
                            <div class="w-12 h-12 bg-blue-500/20 rounded-2xl flex items-center justify-center">
                                <i data-lucide="message-circle" class="w-6 h-6 text-blue-500"></i>
                            </div>
                            <p class="text-zinc-400 font-medium">Bot ha respondido</p>
                        </div>
                        <h2 id="s-replied" class="text-5xl md:text-6xl font-black text-blue-500">0</h2>
                    </div>
                    <div class="glass-card p-8">
                        <div class="flex items-center gap-4 mb-4">
                            <div class="w-12 h-12 bg-zinc-500/20 rounded-2xl flex items-center justify-center">
                                <i data-lucide="users" class="w-6 h-6 text-zinc-400"></i>
                            </div>
                            <p class="text-zinc-400 font-medium">Tráfico Total</p>
                        </div>
                        <h2 id="s-total" class="text-5xl md:text-6xl font-black text-white">0</h2>
                    </div>
                </div>
            </div>

            <!-- CONEXIÓN -->
            <div id="p-conn" class="page">
                <div class="max-w-lg mx-auto">
                    <div class="glass-card p-8 text-center">
                        <div id="qr-container" class="bg-white p-4 rounded-2xl inline-block mb-6">
                            <div id="qr-img" class="w-64 h-64 flex items-center justify-center text-black font-bold text-sm">Esperando...</div>
                        </div>
                        <div id="connected-container" class="hidden mb-6">
                            <div class="w-24 h-24 bg-green-500/20 rounded-full flex items-center justify-center mx-auto mb-4">
                                <i data-lucide="check-circle" class="w-12 h-12 text-green-500"></i>
                            </div>
                            <h2 class="text-2xl font-bold text-green-500 mb-2">WhatsApp Vinculado</h2>
                            <p class="text-zinc-400">El bot está conectado y funcionando.</p>
                        </div>
                        <h2 class="text-2xl font-bold mb-2">Vincular WhatsApp</h2>
                        <p class="text-zinc-500 text-sm mb-6">Escanea el código QR con tu WhatsApp</p>
                        <button id="btn-logout-wa" onclick="logoutWA()" class="hidden btn btn-danger w-full">
                            <i data-lucide="unlink" class="w-5 h-5"></i> Desvincular
                        </button>
                    </div>
                </div>
            </div>

            <!-- RESPUESTAS -->
            <div id="p-train" class="page">
                <div class="flex flex-wrap gap-3 mb-6">
                    <button onclick="downloadTemplate()" class="btn btn-outline"><i data-lucide="download" class="w-5 h-5"></i> Plantilla</button>
                    <button onclick="document.getElementById('import-file').click()" class="btn btn-success"><i data-lucide="upload" class="w-5 h-5"></i> Importar</button>
                    <button onclick="exportTraining()" class="btn btn-warning"><i data-lucide="file-text" class="w-5 h-5"></i> Exportar</button>
                    <input type="file" id="import-file" accept=".txt" class="hidden" onchange="importTraining(this)">
                </div>
                <div class="grid lg:grid-cols-3 gap-6">
                    <div class="lg:col-span-1 glass-card p-6 h-fit">
                        <h3 class="font-bold text-lg mb-4 flex items-center gap-2"><i data-lucide="plus-circle" class="text-blue-500"></i> Nueva Regla</h3>
                        <form id="train-form" enctype="multipart/form-data" onsubmit="saveTrain(event)">
                            <input type="hidden" id="t-id">
                            <input type="text" id="t-key" placeholder="Cuando digan..." class="mb-3" required>
                            <textarea id="t-res" placeholder="Responder..." class="h-32 mb-4" required></textarea>
                            <div class="mb-4">
                                <label class="block text-sm text-zinc-400 mb-2">Tipo de respuesta:</label>
                                <div class="media-type-selector">
                                    <button type="button" onclick="setMediaType('text')" id="mt-text" class="media-type-btn active"><i data-lucide="type" class="w-4 h-4"></i> Texto</button>
                                    <button type="button" onclick="setMediaType('image')" id="mt-image" class="media-type-btn"><i data-lucide="image" class="w-4 h-4"></i> Imagen</button>
                                    <button type="button" onclick="setMediaType('video')" id="mt-video" class="media-type-btn"><i data-lucide="video" class="w-4 h-4"></i> Video</button>
                                </div>
                            </div>
                            <div id="media-upload" class="hidden mb-4">
                                <label class="block text-sm text-zinc-400 mb-2">Archivos (máx 10):</label>
                                <input type="file" id="t-media" accept="image/*,video/*" multiple>
                                <div id="media-preview" class="media-preview-container"></div>
                            </div>
                            <button type="submit" class="btn btn-primary w-full">Guardar Regla</button>
                        </form>
                    </div>
                    <div id="l-train" class="lg:col-span-2 space-y-4"></div>
                </div>
            </div>

            <!-- APRENDER -->
            <div id="p-learn" class="page">
                <h2 class="text-2xl font-bold mb-2">Bandeja de Aprendizaje</h2>
                <p class="text-zinc-500 text-sm mb-6">Mensajes que el bot no supo responder</p>
                <div id="l-learn" class="space-y-3"></div>
            </div>

            <!-- RECORDATORIOS -->
            <div id="p-rem" class="page">
                <div class="glass-card p-6 mb-8">
                    <div class="flex justify-between items-center mb-4">
                        <h3 class="font-bold text-xl">Programar Recordatorio</h3>
                        <span id="rem-clock" class="text-sm text-zinc-500 font-mono"></span>
                    </div>
                    <p class="text-xs text-zinc-500 mb-4">⏰ Los recordatorios usan hora de República Dominicana (AST/UTC-4). Los saltos de línea se conservan.</p>
                    <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
                        <input type="hidden" id="r-id">
                        <input type="text" id="r-name" placeholder="Nombre del cliente">
                        <input type="text" id="r-phone" placeholder="Número (ej: 18091234567)">
                        <textarea id="r-msg" placeholder="Mensaje a enviar (puedes usar saltos de línea)" class="md:col-span-2 h-24"></textarea>
                        <select id="r-freq">
                            <option>Una vez</option>
                            <option>Diario</option>
                            <option>Semanal</option>
                            <option>Mensual</option>
                            <option>Anual</option>
                        </select>
                        <input type="datetime-local" id="r-date">
                    </div>
                    <button onclick="saveRem()" class="btn btn-success mt-6">Programar Recordatorio</button>
                </div>
                <div id="l-rem" class="grid grid-cols-1 md:grid-cols-2 gap-4"></div>
            </div>

            <!-- EXCLUIDOS -->
            <div id="p-excl" class="page">
                <div class="max-w-2xl mx-auto">
                    <div class="glass-card p-6">
                        <h2 class="text-xl font-bold mb-4 flex items-center gap-2"><i data-lucide="shield-off" class="text-red-500"></i> Números Bloqueados</h2>
                        <div class="flex flex-col sm:flex-row gap-2 mb-6">
                            <input type="text" id="e-name" placeholder="Nombre" class="flex-1">
                            <input type="text" id="e-phone" placeholder="Número" class="flex-1">
                            <button onclick="saveExcl()" class="btn btn-primary whitespace-nowrap">Añadir a Bloqueados</button>
                        </div>
                        <div id="l-excl" class="space-y-2"></div>
                    </div>
                </div>
            </div>

            <!-- AJUSTES -->
            <div id="p-config" class="page">
                <div class="grid grid-cols-1 md:grid-cols-2 gap-6 max-w-5xl mx-auto">
                    <div class="glass-card p-8">
                        <h2 class="text-xl font-bold mb-6 flex items-center gap-2"><i data-lucide="key" class="text-blue-500"></i> Credenciales</h2>
                        <input type="text" id="conf-user" placeholder="Nuevo Usuario" class="mb-4">
                        <input type="password" id="conf-pass" placeholder="Nueva Contraseña" class="mb-6">
                        <button onclick="saveCredentials()" class="btn btn-primary w-full">Actualizar Seguridad</button>
                    </div>
                    <div class="glass-card p-8">
                        <h2 class="text-xl font-bold mb-6 flex items-center gap-2"><i data-lucide="shield" class="text-emerald-500"></i> Copias de Seguridad</h2>
                        <div class="mb-6">
                            <p class="text-sm text-zinc-400 mb-2">Número para recibir backups por WhatsApp:</p>
                            <div class="flex gap-2">
                                <input type="text" id="conf-backup-phone" placeholder="Ej: 18091234567" class="flex-1">
                                <button onclick="saveBackupPhone()" class="btn btn-success flex items-center gap-1">
                                    <i data-lucide="save" class="w-5 h-5"></i> Guardar
                                </button>
                            </div>
                            <p id="phone-saved-msg" class="text-xs mt-2 hidden"></p>
                        </div>
                        <div class="space-y-3">
                            <button onclick="downloadBackup()" class="btn btn-outline w-full"><i data-lucide="download" class="w-5 h-5"></i> Descargar Backup</button>
                            <button onclick="sendBackupManually()" class="btn btn-primary w-full"><i data-lucide="send" class="w-5 h-5"></i> Enviar a WhatsApp</button>
                            <button onclick="document.getElementById('restore-file').click()" class="btn btn-warning w-full"><i data-lucide="upload" class="w-5 h-5"></i> Restaurar Backup</button>
                            <input type="file" id="restore-file" accept=".json" class="hidden" onchange="restoreBackup(this)">
                        </div>
                        <p class="text-xs text-zinc-500 mt-4">💡 Backup automático diario a las 12:00 AM hora RD.</p>
                    </div>
                </div>
            </div>
        </div>
    </main>

    <script>
        const socket = io();
        let db = { training:[], learning:[], reminders:[], excluded:[], stats:{ replied:0, total:0 }, backupPhone:'' };
        let currentMediaType = 'text';
        let selectedFiles = [];

        function toggleSidebar() { document.getElementById('sidebar').classList.toggle('-translate-x-full'); }

        function nav(id, noToggle = false) {
            document.querySelectorAll('.page').forEach(p => p.classList.remove('active'));
            document.querySelectorAll('.sidebar-item').forEach(i => i.classList.remove('active'));
            document.getElementById('p-'+id).classList.add('active');
            document.getElementById('n-'+id).classList.add('active');
            if (!noToggle && window.innerWidth < 1024) toggleSidebar();
            lucide.createIcons();
        }

        function updateClock() {
            const now = new Date();
            const rdTime = new Date(now.toLocaleString('en-US', { timeZone: 'America/Santo_Domingo' }));
            const h = String(rdTime.getHours()).padStart(2,'0');
            const m = String(rdTime.getMinutes()).padStart(2,'0');
            const s = String(rdTime.getSeconds()).padStart(2,'0');
            const timeStr = h + ':' + m + ':' + s + ' RD';
            const el1 = document.getElementById('server-clock');
            const el2 = document.getElementById('rem-clock');
            if (el1) el1.textContent = '🕐 ' + timeStr;
            if (el2) el2.textContent = '🕐 ' + timeStr;
        }
        setInterval(updateClock, 1000);
        updateClock();

        function setMediaType(type) {
            currentMediaType = type;
            document.querySelectorAll('.media-type-btn').forEach(b => b.classList.remove('active'));
            document.getElementById('mt-'+type).classList.add('active');
            if (type === 'text') {
                document.getElementById('media-upload').classList.add('hidden');
                selectedFiles = [];
            } else {
                document.getElementById('media-upload').classList.remove('hidden');
                document.getElementById('t-media').accept = type === 'image' ? 'image/*' : 'video/*';
            }
            lucide.createIcons();
        }

        document.getElementById('t-media').addEventListener('change', function(e) {
            const files = Array.from(e.target.files);
            if (files.length > 10) { alert('Máximo 10'); return; }
            selectedFiles = files;
            const preview = document.getElementById('media-preview');
            preview.innerHTML = '';
            files.forEach((file, index) => {
                const reader = new FileReader();
                reader.onload = function(ev) {
                    const div = document.createElement('div');
                    div.className = 'media-item';
                    if (file.type.startsWith('image/')) {
                        div.innerHTML = '<img src="'+ev.target.result+'" class="media-preview"><div class="media-remove" onclick="removeMediaFile('+index+')">×</div>';
                    } else {
                        div.innerHTML = '<video src="'+ev.target.result+'" class="media-preview" controls></video><div class="media-remove" onclick="removeMediaFile('+index+')">×</div>';
                    }
                    preview.appendChild(div);
                };
                reader.readAsDataURL(file);
            });
        });

        function removeMediaFile(index) {
            selectedFiles.splice(index, 1);
            const dt = new DataTransfer();
            selectedFiles.forEach(file => dt.items.add(file));
            document.getElementById('t-media').files = dt.files;
            document.getElementById('t-media').dispatchEvent(new Event('change'));
        }

        socket.on('status_update', s => {
            document.getElementById('bot-status').innerText = s;
            document.getElementById('dot').className = s === 'Conectado'
                ? 'w-2.5 h-2.5 rounded-full bg-green-500'
                : 'w-2.5 h-2.5 rounded-full bg-red-500 animate-pulse';
        });

        socket.on('connection_status', data => {
            if (data.connected) {
                document.getElementById('qr-container').classList.add('hidden');
                document.getElementById('connected-container').classList.remove('hidden');
                document.getElementById('btn-logout-wa').classList.remove('hidden');
            } else {
                document.getElementById('qr-container').classList.remove('hidden');
                document.getElementById('connected-container').classList.add('hidden');
                document.getElementById('btn-logout-wa').classList.add('hidden');
            }
            lucide.createIcons();
        });

        socket.on('qr_update', url => {
            document.getElementById('qr-img').innerHTML = '<img src="'+url+'" class="w-full">';
        });

        socket.on('data_update', data => { db = data; render(); });

        async function load() {
            try {
                const res = await fetch('/api/data');
                if (res.status === 401) { location.href = '/login'; return; }
                const data = await res.json();
                db = data;

                if (data.isConnected) {
                    document.getElementById('qr-container').classList.add('hidden');
                    document.getElementById('connected-container').classList.remove('hidden');
                    document.getElementById('btn-logout-wa').classList.remove('hidden');
                    document.getElementById('bot-status').innerText = 'Conectado';
                    document.getElementById('dot').className = 'w-2.5 h-2.5 rounded-full bg-green-500';
                } else {
                    document.getElementById('bot-status').innerText = data.botStatus || 'Desconectado';
                    document.getElementById('dot').className = 'w-2.5 h-2.5 rounded-full bg-red-500 animate-pulse';
                }

                document.getElementById('conf-backup-phone').value = data.backupPhone || '';
                render();
                lucide.createIcons();
            } catch(e) { console.error(e); }
        }

        function esc(text) {
            if (!text) return '';
            const d = document.createElement('div');
            d.appendChild(document.createTextNode(text));
            return d.innerHTML;
        }

        function formatReminderDate(dateStr) {
            if (!dateStr) return '';
            try {
                const d = new Date(dateStr);
                const day = String(d.getDate()).padStart(2,'0');
                const month = String(d.getMonth()+1).padStart(2,'0');
                const year = d.getFullYear();
                const h = String(d.getHours()).padStart(2,'0');
                const m = String(d.getMinutes()).padStart(2,'0');
                const ampm = d.getHours() >= 12 ? 'PM' : 'AM';
                const h12 = d.getHours() % 12 || 12;
                return day+'/'+month+'/'+year+' '+h12+':'+m+' '+ampm;
            } catch(e) { return dateStr; }
        }

        function render() {
            document.getElementById('s-replied').innerText = db.stats ? db.stats.replied : 0;
            document.getElementById('s-total').innerText = db.stats ? db.stats.total : 0;

            document.getElementById('l-train').innerHTML = (db.training || []).map((t,i) =>
                `<div class="glass-card p-5">
                    <div class="flex justify-between items-start gap-3">
                        <div class="flex-1 min-w-0">
                            <div class="flex items-center gap-2 mb-1 flex-wrap">
                                <span class="text-blue-400 font-semibold">P:</span>
                                <span class="font-medium break-all">${esc(t.key)}</span>
                                ${t.mediaPaths && t.mediaPaths.length > 0 ? `<span class="text-xs bg-blue-500/20 text-blue-400 px-3 py-1 rounded-full">${t.mediaPaths.length} archivo(s)</span>` : ''}
                            </div>
                            <p class="text-sm text-zinc-300 break-all whitespace-pre-wrap">${esc(t.response)}</p>
                        </div>
                        <div class="flex gap-1">
                            <button onclick="editT(${i})" class="p-2 text-zinc-400 hover:text-white hover:bg-white/10 rounded-xl transition"><i data-lucide="edit-3" class="w-4 h-4"></i></button>
                            <button onclick="delT(${i})" class="p-2 text-red-400 hover:text-red-500 hover:bg-red-500/10 rounded-xl transition"><i data-lucide="trash-2" class="w-4 h-4"></i></button>
                        </div>
                    </div>
                    ${t.mediaPaths && t.mediaPaths.length > 0 ? `
                    <div class="media-preview-container mt-3">
                        ${t.mediaPaths.map((p, idx) => (t.mediaTypes[idx] && t.mediaTypes[idx].includes('image')) ? 
                            `<img src="/${p}" class="media-preview">` : 
                            `<video src="/${p}" class="media-preview" controls></video>`).join('')}
                    </div>` : ''}
                </div>`
            ).join('');

            document.getElementById('l-learn').innerHTML = (!db.learning || db.learning.length === 0)
                ? '<div class="glass-card p-8 text-center text-zinc-500">No hay conversaciones nuevas</div>'
                : db.learning.map((l,i) =>
                    `<div class="glass-card p-4 flex flex-col sm:flex-row justify-between items-start sm:items-center gap-3">
                        <div class="min-w-0 flex-1">
                            <span class="text-xs text-zinc-500">${l.date} - ${l.from}</span>
                            <p class="font-medium break-all whitespace-pre-wrap">${esc(l.text)}</p>
                        </div>
                        <div class="flex gap-2">
                            <button onclick="useL(${i})" class="btn btn-primary text-sm py-2 px-4">Usar</button>
                            <button onclick="delL(${i})" class="p-2 text-red-400 hover:bg-red-500/10 rounded-xl"><i data-lucide="x" class="w-5 h-5"></i></button>
                        </div>
                    </div>`
                ).join('');

            document.getElementById('l-rem').innerHTML = (db.reminders || []).map((r,i) =>
                `<div class="glass-card p-5 border-l-4 border-emerald-500">
                    <div class="flex justify-between items-start">
                        <h3 class="font-bold text-lg">${esc(r.name)}</h3>
                        <div class="flex gap-1">
                            <button onclick="editR(${i})" class="p-2 text-zinc-400 hover:text-white"><i data-lucide="edit-3" class="w-4 h-4"></i></button>
                            <button onclick="delR(${i})" class="p-2 text-red-400"><i data-lucide="trash-2" class="w-4 h-4"></i></button>
                        </div>
                    </div>
                    <p class="text-sm text-zinc-400 mb-2">📱 ${esc(r.phone)}</p>
                    <p class="text-sm text-zinc-300 mb-3 whitespace-pre-wrap">${esc(r.message)}</p>
                    <div class="flex flex-wrap gap-2">
                        <span class="text-xs font-bold bg-emerald-500/20 text-emerald-400 px-3 py-1 rounded-full">${r.freq}</span>
                        <span class="text-xs font-bold bg-blue-500/20 text-blue-400 px-3 py-1 rounded-full">📅 ${formatReminderDate(r.date)}</span>
                    </div>
                </div>`
            ).join('');

            document.getElementById('l-excl').innerHTML = (db.excluded || []).map((e,i) =>
                `<div class="glass-card p-3 flex justify-between items-center">
                    <span class="text-sm">${esc(e.name)} (${esc(e.phone)})</span>
                    <button onclick="delE(${i})" class="text-red-400 hover:text-red-500 p-1"><i data-lucide="user-minus" class="w-5 h-5"></i></button>
                </div>`
            ).join('');

            lucide.createIcons();
        }

        async function saveTrain(e) {
            e.preventDefault();
            const fd = new FormData();
            fd.append('id', document.getElementById('t-id').value);
            fd.append('key', document.getElementById('t-key').value);
            fd.append('response', document.getElementById('t-res').value);
            if (currentMediaType !== 'text' && selectedFiles.length > 0) selectedFiles.forEach(f => fd.append('media', f));
            await fetch('/api/train', { method:'POST', body: fd });
            document.getElementById('t-id').value=""; document.getElementById('t-key').value=""; document.getElementById('t-res').value="";
            document.getElementById('t-media').value=""; document.getElementById('media-preview').innerHTML="";
            selectedFiles=[]; setMediaType('text'); load();
        }

        function editT(i) {
            const t = db.training[i];
            document.getElementById('t-id').value = i; document.getElementById('t-key').value = t.key; document.getElementById('t-res').value = t.response;
            if (t.mediaPaths && t.mediaPaths.length > 0 && t.mediaTypes && t.mediaTypes[0]) setMediaType(t.mediaTypes[0].includes('image') ? 'image' : 'video');
            window.scrollTo({ top: 0, behavior: 'smooth' });
        }

        async function delT(i) { if (confirm('¿Eliminar?')) { await fetch('/api/train/'+i, {method:'DELETE'}); load(); } }
        function useL(i) { document.getElementById('t-key').value = db.learning[i].text; nav('train', true); setTimeout(() => document.getElementById('t-res').focus(), 300); }
        async function delL(i) { await fetch('/api/learning/'+i, {method:'DELETE'}); load(); }

        async function saveRem() {
            const data = {
                id: document.getElementById('r-id').value,
                name: document.getElementById('r-name').value,
                phone: document.getElementById('r-phone').value,
                message: document.getElementById('r-msg').value,
                freq: document.getElementById('r-freq').value,
                date: document.getElementById('r-date').value
            };
            if (!data.name || !data.phone || !data.message || !data.date) { alert('Completa todos los campos'); return; }
            await fetch('/api/reminders', { method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify(data) });
            document.getElementById('r-id').value=""; document.getElementById('r-name').value="";
            document.getElementById('r-phone').value=""; document.getElementById('r-msg').value=""; document.getElementById('r-date').value="";
            load();
        }

        function editR(i) {
            const r = db.reminders[i];
            document.getElementById('r-id').value = i;
            document.getElementById('r-name').value = r.name;
            document.getElementById('r-phone').value = r.phone;
            document.getElementById('r-msg').value = r.message; // El textarea mostrará saltos de línea
            document.getElementById('r-freq').value = r.freq;
            document.getElementById('r-date').value = r.date;
            window.scrollTo({ top: 0, behavior: 'smooth' });
        }

        async function delR(i) { if (confirm('¿Eliminar?')) { await fetch('/api/reminders/'+i, {method:'DELETE'}); load(); } }

        async function saveExcl() {
            const name = document.getElementById('e-name').value, phone = document.getElementById('e-phone').value;
            if (!name || !phone) { alert('Completa los campos'); return; }
            await fetch('/api/exclude', { method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify({name,phone}) });
            document.getElementById('e-name').value=""; document.getElementById('e-phone').value=""; load();
        }

        async function delE(i) { if (confirm('¿Eliminar?')) { await fetch('/api/exclude/'+i, {method:'DELETE'}); load(); } }

        async function saveCredentials() {
            const user = document.getElementById('conf-user').value, pass = document.getElementById('conf-pass').value;
            if (!user && !pass) { alert('Ingresa al menos un campo'); return; }
            await fetch('/api/config/credentials', { method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify({user,pass}) });
            alert("Credenciales actualizadas. Inicia sesión de nuevo."); location.href='/login';
        }

        async function saveBackupPhone() {
            const bp = document.getElementById('conf-backup-phone').value.replace(/\D/g, '');
            const msg = document.getElementById('phone-saved-msg');
            const res = await fetch('/api/config/backup-phone', { method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify({backupPhone:bp}) });
            const data = await res.json();
            msg.classList.remove('hidden');
            if (data.ok) { msg.textContent='✅ Número guardado'; msg.className='text-xs mt-2 text-green-500'; }
            else { msg.textContent='❌ Error'; msg.className='text-xs mt-2 text-red-500'; }
            setTimeout(() => msg.classList.add('hidden'), 3000);
        }

        function downloadBackup() { window.location.href='/api/backup/download'; }
        function downloadTemplate() { window.location.href='/api/train/template'; }
        function exportTraining() { window.location.href='/api/train/export'; }

        async function sendBackupManually() {
            const phone = document.getElementById('conf-backup-phone').value;
            if (!phone || phone.trim()==='') { alert('⚠️ Guarda un número primero'); return; }
            if (!confirm('¿Enviar backup ahora?')) return;
            const res = await fetch('/api/backup/send', {method:'POST'});
            const data = await res.json();
            alert(data.ok ? '✅ '+data.message : '❌ '+data.message);
        }

        async function restoreBackup(input) {
            if (!input.files[0]) return;
            if (!confirm('⚠️ ¿Restaurar backup?')) { input.value=''; return; }
            const fd = new FormData(); fd.append('backup', input.files[0]);
            const res = await fetch('/api/backup/restore', {method:'POST', body:fd});
            const data = await res.json();
            if (data.ok) { alert('✅ Restaurado'); setTimeout(() => location.reload(), 1000); }
            else alert('❌ Error: '+(data.error||''));
            input.value='';
        }

        async function importTraining(input) {
            if (!input.files[0]) return;
            const fd = new FormData(); fd.append('file', input.files[0]);
            const res = await fetch('/api/train/import', {method:'POST', body:fd});
            const data = await res.json();
            if (data.ok) alert('✅ '+data.imported+' respuestas importadas');
            else alert('❌ Error: '+(data.error||''));
            input.value=''; load();
        }

        async function logoutWA() {
            if (confirm("¿Desvincular? Los contadores se reiniciarán.")) {
                await fetch('/api/logout-wa', {method:'POST'});
                setTimeout(() => location.reload(), 1500);
            }
        }

        window.onload = load;
        lucide.createIcons();
    </script>
</body>
</html>
HTMLEOF

# ==================== LOGIN.HTML (sin cambios) ====================
cat <<'LOGINEOF' > views/login.html
<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>GZMBOT | Login</title>
    <script src="https://cdn.tailwindcss.com"></script>
    <link href="https://fonts.googleapis.com/css2?family=Plus+Jakarta+Sans:wght@400;600;800&display=swap" rel="stylesheet">
    <style>
        body { background: #0a0a0f; font-family: 'Plus Jakarta Sans', sans-serif; height: 100vh; display: flex; align-items: center; justify-content: center; margin: 0; padding: 16px; }
        .glass-card { background: rgba(20, 20, 30, 0.8); backdrop-filter: blur(20px); border: 1px solid rgba(255,255,255,0.05); border-radius: 40px; padding: 40px; width: 100%; max-width: 420px; box-shadow: 0 30px 60px -20px rgba(0,0,0,0.8); }
        .gradient-text { background: linear-gradient(135deg, #fff 0%, #94a3b8 100%); -webkit-background-clip: text; -webkit-text-fill-color: transparent; }
    </style>
</head>
<body>
    <div class="glass-card text-center">
        <h1 class="text-4xl font-black mb-2 gradient-text">GZMBOT</h1>
        <p class="text-blue-500 font-semibold text-xs uppercase tracking-[0.3em] mb-8">Administrative Panel</p>
        <form onsubmit="login(event)" class="space-y-5">
            <input type="text" id="u" placeholder="Usuario maestro" class="w-full p-4 bg-[#1a1a24] border border-[#2a2a35] rounded-2xl text-white outline-none focus:border-blue-600 transition" required>
            <input type="password" id="p" placeholder="Contraseña" class="w-full p-4 bg-[#1a1a24] border border-[#2a2a35] rounded-2xl text-white outline-none focus:border-blue-600 transition" required>
            <button type="submit" class="w-full py-4 bg-gradient-to-r from-blue-600 to-blue-800 rounded-2xl text-white font-bold hover:scale-[1.02] active:scale-95 transition-all shadow-lg shadow-blue-600/20">ACCEDER AL PANEL</button>
        </form>
    </div>
    <script>
        async function login(e) {
            e.preventDefault();
            const r = await fetch('/login', { method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify({user:document.getElementById('u').value, pass:document.getElementById('p').value}) });
            const d = await r.json();
            if (d.ok) location.href='/'; else alert("Credenciales incorrectas");
        }
    </script>
</body>
</html>
LOGINEOF

print_success "Interfaz web creada"

# ==================== INSTALAR DEPENDENCIAS NPM ====================
print_step "INSTALANDO PAQUETES NPM"

npm install -g pm2 &> /dev/null && print_success "PM2 instalado globalmente"

cd $INSTALL_DIR
npm install whatsapp-web.js qrcode express socket.io express-session puppeteer moment-timezone node-cron multer --omit=dev &> /dev/null && print_success "Dependencias Node.js instaladas"

# ==================== CONFIGURAR PM2 ====================
print_step "CONFIGURANDO PM2"

# Crear archivo ecosystem
cat <<EOF > ecosystem.config.js
module.exports = {
  apps: [{
    name: 'gzmbot',
    script: 'app.js',
    cwd: '$INSTALL_DIR',
    env: {
      TZ: 'America/Santo_Domingo',
      PUPPETEER_EXECUTABLE_PATH: '$CHROME_PATH',
      NODE_ENV: 'production'
    },
    watch: false,
    max_memory_restart: '500M',
    error_file: '$INSTALL_DIR/error.log',
    out_file: '$INSTALL_DIR/out.log',
    log_file: '$INSTALL_DIR/combined.log',
    time: true
  }]
}
EOF

pm2 delete gzmbot &> /dev/null || true
pm2 start ecosystem.config.js &> /dev/null && print_success "Bot iniciado con PM2"
pm2 save &> /dev/null
pm2 startup &> /dev/null

# ==================== CONFIGURAR PERMISOS ====================
print_step "AJUSTANDO PERMISOS"

chown -R $SUDO_USER:$SUDO_USER $INSTALL_DIR 2>/dev/null || chown -R root:root $INSTALL_DIR
chmod -R 755 $INSTALL_DIR
print_success "Permisos configurados"

# ==================== CONFIGURAR FIREWALL ====================
print_step "CONFIGURANDO FIREWALL"

if command -v ufw &> /dev/null; then
    ufw allow 80/tcp &> /dev/null && print_success "Puerto 80 abierto en firewall"
else
    print_warning "UFW no instalado, omite configuración de firewall"
fi

# ==================== OBTENER IP PÚBLICA (IPv4 preferida) ====================
print_step "DETECTANDO DIRECCIÓN IP"

# Intentar obtener IPv4 pública
IPV4=$(curl -4 -s ifconfig.me 2>/dev/null || curl -4 -s icanhazip.com 2>/dev/null || echo "")

if [ -z "$IPV4" ]; then
    # Si no hay IPv4 pública, usar IP local
    IPV4=$(hostname -I | awk '{print $1}')
fi

print_success "IP detectada: $IPV4"

# ==================== MOSTRAR RESUMEN FINAL ====================
clear
echo -e "${MAGENTA}"
echo '    ██████╗ ███████╗███╗   ███╗██████╗  ██████╗ ████████╗'
echo '   ██╔════╝ ╚══███╔╝████╗ ████║██╔══██╗██╔═══██╗╚══██╔══╝'
echo '   ██║  ███╗  ███╔╝ ██╔████╔██║██████╔╝██║   ██║   ██║   '
echo '   ██║   ██║ ███╔╝  ██║╚██╔╝██║██╔══██╗██║   ██║   ██║   '
echo '   ╚██████╔╝███████╗██║ ╚═╝ ██║██████╔╝╚██████╔╝   ██║   '
echo '    ╚═════╝ ╚══════╝╚═╝     ╚═╝╚═════╝  ╚═════╝    ╚═╝   '
echo -e "${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"
echo -e "${WHITE}            INSTALACIÓN COMPLETADA CON ÉXITO${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}\n"

echo -e "${CYAN}🌐 PANEL WEB:${NC} ${WHITE}http://$IPV4${NC}"
echo -e "${CYAN}👤 USUARIO:${NC} ${WHITE}$ADMIN_USER${NC}"
echo -e "${CYAN}🔐 CONTRASEÑA:${NC} ${WHITE}$ADMIN_PASS${NC}"
echo -e "${CYAN}🕐 ZONA HORARIA:${NC} ${WHITE}America/Santo_Domingo (RD)${NC}"
echo -e "${CYAN}📁 RUTA:${NC} ${WHITE}$INSTALL_DIR${NC}\n"

echo -e "${YELLOW}════════════════════════ COMANDOS ÚTILES ════════════════════════${NC}"
echo -e " ${GREEN}▶${NC} Ver estado: ${WHITE}pm2 status${NC}"
echo -e " ${GREEN}▶${NC} Ver logs: ${WHITE}pm2 logs gzmbot${NC}"
echo -e " ${GREEN}▶${NC} Reiniciar bot: ${WHITE}pm2 restart gzmbot${NC}"
echo -e " ${GREEN}▶${NC} Detener bot: ${WHITE}pm2 stop gzmbot${NC}\n"

echo -e "${BLUE}════════════════════════ NOTAS IMPORTANTES ════════════════════════${NC}"
echo -e " ${WHITE}•${NC} Si el QR no aparece en 30 segundos, verifica los logs."
echo -e " ${WHITE}•${NC} Para limpiar sesión: ${WHITE}rm -rf $INSTALL_DIR/.wwebjs_auth/*${NC}"
echo -e " ${WHITE}•${NC} El backup automático se realiza a las 12:00 AM hora RD.\n"

echo -e "${GREEN}═══════════════════════════════════════════════════════════════════${NC}\n"