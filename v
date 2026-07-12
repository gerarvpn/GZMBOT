#!/bin/bash
# ============================================================
# GZMBOT - INSTALACIÓN DEFINITIVA CON MENÚ INTERACTIVO (v8)
# ============================================================
# - Hora de backup persistente (no se restablece).
# - Procesamiento de mensajes fiable.
# - Copia de seguridad robusta con logs detallados.
# - Máxima estabilidad y bajo consumo.
# ============================================================

clear
echo "============================================================="
echo "  GZMBOT - Instalación con Menú Interactivo (v8)"
echo "============================================================="

if [ "$EUID" -ne 0 ]; then 
    echo "❌ Ejecuta como root (sudo)."
    exit 1
fi

# Credenciales iniciales
read -p "Usuario Maestro: " ADMIN_USER
read -sp "Contraseña Maestra: " ADMIN_PASS
echo
read -p "Dominio (ej. gzmbot.com): " DOMAIN

if [ -z "$DOMAIN" ]; then
    echo "❌ Dominio requerido."
    exit 1
fi

echo "▶️ Iniciando instalación..."

# Función para apt-get con espera infinita
apt_install() {
    apt-get -o DPkg::Lock::Timeout=-1 install -y -qq --no-install-recommends "$@"
}

# 1. Dependencias del sistema
echo "📦 Instalando dependencias del sistema..."
apt-get -o DPkg::Lock::Timeout=-1 update -qq
apt_install nginx curl wget ca-certificates build-essential sqlite3 libsqlite3-dev lsof cron openssl

# 2. Google Chrome Stable
echo "🌐 Instalando Google Chrome..."
wget -q -O - https://dl.google.com/linux/linux_signing_key.pub | tee /etc/apt/trusted.gpg.d/google.asc > /dev/null
echo "deb [arch=amd64] http://dl.google.com/linux/chrome/deb/ stable main" | tee /etc/apt/sources.list.d/google-chrome.list
apt-get -o DPkg::Lock::Timeout=-1 update -qq
apt_install google-chrome-stable

# 3. Node.js 20 LTS
echo "📦 Instalando Node.js 20 LTS..."
curl -fsSL https://deb.nodesource.com/setup_20.x | bash - > /dev/null 2>&1
apt_install nodejs

# 4. Zona horaria
timedatectl set-timezone America/Santo_Domingo 2>/dev/null || true

# 5. acme.sh
echo "🔒 Instalando acme.sh..."
curl -s https://get.acme.sh | sh -s email=admin@$DOMAIN > /dev/null 2>&1
source ~/.acme.sh/acme.sh.env

# 6. Directorios
echo "📁 Creando estructura..."
mkdir -p $HOME/gzmbot/{views,data,media,backups,workers}
mkdir -p /var/www/html /etc/nginx/ssl
cd $HOME/gzmbot

# 7. Configuración
echo "📝 Creando config.json..."
cat <<EOF > config.json
{
  "adminUser": "$ADMIN_USER",
  "adminPassword": "$ADMIN_PASS",
  "port": 3000,
  "sessionSecret": "$(openssl rand -hex 24)",
  "backupPhone": "",
  "backupHour": "12:00",
  "responseDelay": 0,
  "queueInterval": 3000
}
EOF

# ============================================================
# 8. app.js (backend con todas las mejoras)
# ============================================================
echo "⚙️ Generando app.js..."
cat <<'APPEOF' > app.js
process.env.TZ = 'America/Santo_Domingo';
process.env.NODE_OPTIONS = '--max-old-space-size=64';

const { Client, LocalAuth, MessageMedia } = require('whatsapp-web.js');
const qrcode = require('qrcode');
const express = require('express');
const http = require('http');
const socketIo = require('socket.io');
const session = require('express-session');
const fs = require('fs');
const path = require('path');
const os = require('os');
const { exec } = require('child_process');
const moment = require('moment-timezone');
const multer = require('multer');
const Database = require('better-sqlite3');
const fsPromises = fs.promises;

const TZ = 'America/Santo_Domingo';
const app = express();
app.set('trust proxy', 1);

const server = http.createServer(app);
const io = socketIo(server, {
    pingTimeout: 60000,
    pingInterval: 25000,
    transports: ['websocket', 'polling']
});

const DB_PATH = path.join(__dirname, 'data/database.sqlite');
const CONFIG_PATH = path.join(__dirname, 'config.json');
const MEDIA_PATH = path.join(__dirname, 'media');
const BACKUP_PATH = path.join(__dirname, 'backups');
const AUTH_PATH = path.join(__dirname, '.wwebjs_auth');
const WORKERS_PATH = path.join(__dirname, 'workers');

if (!fs.existsSync(WORKERS_PATH)) fs.mkdirSync(WORKERS_PATH, { recursive: true });
if (!fs.existsSync(MEDIA_PATH)) fs.mkdirSync(MEDIA_PATH, { recursive: true });

server.listen(3000, '0.0.0.0', () => console.log('🚀 Servidor activo en puerto 3000.'));

let dbSqlite;
try {
    dbSqlite = new Database(DB_PATH);
    dbSqlite.pragma('journal_mode = WAL');
    dbSqlite.pragma('synchronous = NORMAL');
    dbSqlite.pragma('temp_store = MEMORY');
    dbSqlite.pragma('busy_timeout = 5000');
    
    dbSqlite.exec(`
        CREATE TABLE IF NOT EXISTS training (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            key TEXT NOT NULL,
            response TEXT NOT NULL,
            mediaPaths TEXT,
            mediaTypes TEXT
        );
        CREATE TABLE IF NOT EXISTS reminders (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            phone TEXT NOT NULL,
            message TEXT NOT NULL,
            freq TEXT NOT NULL,
            date TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS excluded (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            phone TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS stats (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            replied INTEGER DEFAULT 0,
            total INTEGER DEFAULT 0,
            lastBackupDate TEXT
        );
        CREATE TABLE IF NOT EXISTS websites (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            slug TEXT NOT NULL UNIQUE,
            content TEXT NOT NULL,
            created_at TEXT DEFAULT (datetime('now', 'localtime')),
            updated_at TEXT DEFAULT (datetime('now', 'localtime'))
        );
        CREATE INDEX IF NOT EXISTS idx_reminders_date ON reminders(date);
        CREATE INDEX IF NOT EXISTS idx_excluded_phone ON excluded(phone);
        CREATE INDEX IF NOT EXISTS idx_websites_slug ON websites(slug);
    `);

    const statsRow = dbSqlite.prepare('SELECT COUNT(*) as count FROM stats').get();
    if (statsRow.count === 0) {
        dbSqlite.prepare('INSERT INTO stats (replied, total, lastBackupDate) VALUES (0, 0, NULL)').run();
    }
} catch (sqliteErr) {
    console.error("⚠️ Error SQLite:", sqliteErr.message);
}

const storage = multer.diskStorage({
    destination: (req, file, cb) => cb(null, MEDIA_PATH),
    filename: (req, file, cb) => {
        const safeName = file.originalname.replace(/[^a-zA-Z0-9.]/g, "_");
        cb(null, Date.now() + '-' + safeName);
    }
});
const upload = multer({
    storage,
    limits: { fileSize: 10 * 1024 * 1024 }
});

app.use((err, req, res, next) => {
    if (err instanceof multer.MulterError) {
        return res.status(400).json({ ok: false, error: 'Error de archivo: ' + err.message });
    }
    next(err);
});

app.use(express.json());
app.use(express.urlencoded({ extended: true }));
app.use('/media', express.static(MEDIA_PATH));

const getConfig = () => {
    try { return JSON.parse(fs.readFileSync(CONFIG_PATH)); }
    catch (e) { return { adminUser: "admin", adminPassword: "password", sessionSecret: "fallback", responseDelay: 0, queueInterval: 3000, backupPhone: "", backupHour: "12:00" }; }
};

app.use(session({
    secret: getConfig().sessionSecret || 'gzm_default',
    resave: false,
    saveUninitialized: true,
    cookie: { maxAge: 86400000, secure: false }
}));

// Caché
let cachedDB = null;
let cacheTimestamp = 0;
const CACHE_TTL = 5000;

function getDB() {
    const now = Date.now();
    if (cachedDB && (now - cacheTimestamp) < CACHE_TTL) return cachedDB;
    try {
        const training = dbSqlite.prepare('SELECT * FROM training').all();
        const reminders = dbSqlite.prepare('SELECT * FROM reminders').all();
        const excluded = dbSqlite.prepare('SELECT * FROM excluded').all();
        const stats = dbSqlite.prepare('SELECT * FROM stats LIMIT 1').get() || { replied: 0, total: 0, lastBackupDate: null };
        const websites = dbSqlite.prepare('SELECT * FROM websites ORDER BY id DESC').all();
        cachedDB = { training, reminders, excluded, stats, websites };
        cacheTimestamp = now;
        return cachedDB;
    } catch (e) {
        return { training: [], reminders: [], excluded: [], stats: { replied: 0, total: 0, lastBackupDate: null }, websites: [] };
    }
}

function invalidateCache() { cachedDB = null; cacheTimestamp = 0; }

let dataUpdateTimeout = null;
function emitDataUpdate() {
    if (dataUpdateTimeout) return;
    dataUpdateTimeout = setTimeout(() => {
        io.emit('data_update', getDB());
        dataUpdateTimeout = null;
    }, 500);
}

function updateStats(repliedInc, totalInc) {
    try {
        dbSqlite.prepare('UPDATE stats SET replied = replied + ?, total = total + ?').run(repliedInc, totalInc);
        invalidateCache();
        emitDataUpdate();
    } catch (e) {}
}

function normalizePhone(phone) {
    if (!phone) return '';
    return phone.split('@')[0].replace(/[^\d]/g, '').trim();
}

// ===== FUNCIÓN DE ENVÍO ROBUSTA CON REINTENTOS Y LOGS =====
async function sendMessage(chatId, message, options = {}, retries = 3) {
    if (!isConnected || !client) {
        console.warn(`⚠️ No conectado, no se puede enviar a ${chatId}`);
        return false;
    }
    let fullChatId = chatId;
    if (!fullChatId.includes('@')) {
        fullChatId = fullChatId + '@c.us';
    }
    fullChatId = fullChatId.trim();
    
    for (let attempt = 1; attempt <= retries; attempt++) {
        try {
            console.log(`📤 Enviando a ${fullChatId} (intento ${attempt}/${retries})`);
            await client.sendMessage(fullChatId, message, options);
            console.log(`✅ Mensaje enviado a ${fullChatId}`);
            return true;
        } catch (err) {
            console.error(`❌ Error intento ${attempt} a ${fullChatId}: ${err.message}`);
            if (attempt < retries) {
                const delay = attempt * 2000;
                console.log(`⏳ Reintentando en ${delay/1000}s...`);
                await new Promise(r => setTimeout(r, delay));
            } else {
                console.error(`❌ Fallo definitivo a ${fullChatId}`);
            }
        }
    }
    return false;
}

// Métricas cada 60 segundos (mínimo consumo)
const cpuCores = os.cpus().length;
function emitSystemStats() {
    try {
        const loadAvg = os.loadavg()[0];
        let cpuUsage = Math.min(100, Math.max(0, (loadAvg / cpuCores) * 100));
        const totalMem = os.totalmem();
        const freeMem = os.freemem();
        const ramUsage = ((totalMem - freeMem) / totalMem) * 100;
        io.emit('sys_stats', { cpu: parseFloat(cpuUsage.toFixed(1)), ram: parseFloat(ramUsage.toFixed(1)), uptime: os.uptime() });
    } catch (err) {}
}
setInterval(emitSystemStats, 60000);

// Cola de mensajes optimizada
class MessageQueue {
    constructor(intervalMs = 3000) {
        this.queue = [];
        this.intervalMs = intervalMs;
        this.maxSize = 300;
        this.retryLimit = 2;
        this.processing = false;
        this.timer = null;
        this.start();
    }
    start() {
        if (this.timer) clearInterval(this.timer);
        this.timer = setInterval(() => this.process(), this.intervalMs);
    }
    enqueue(chatId, message, options = {}) {
        if (this.queue.length >= this.maxSize) { console.warn('⚠️ Cola llena'); return; }
        this.queue.push({ chatId, message, options, attempts: 0 });
        console.log(`📥 Mensaje encolado para ${chatId}`);
    }
    async process() {
        if (this.processing || this.queue.length === 0) return;
        this.processing = true;
        const item = this.queue.shift();
        const { chatId, message, options, attempts } = item;
        try {
            const success = await sendMessage(chatId, message, options, 2);
            if (!success && attempts < this.retryLimit) {
                item.attempts++;
                this.queue.unshift(item);
                console.log(`🔄 Reencolando mensaje a ${chatId} (intento ${item.attempts})`);
            } else if (!success) {
                console.error(`❌ Fallo definitivo mensaje a ${chatId}`);
            }
        } catch (err) {
            if (attempts < this.retryLimit) {
                item.attempts++;
                this.queue.unshift(item);
            } else {
                console.error(`❌ Fallo mensaje: ${err.message}`);
            }
        }
        this.processing = false;
    }
    setInterval(ms) {
        this.intervalMs = ms;
        this.start();
    }
    size() { return this.queue.length; }
}

let client, botStatus = "Desconectado", lastQRImage = null, isConnected = false, contacts = [], contactsHash = '', messageQueue;
let reconnectAttempts = 0, reconnectTimeout = null, pairingCodeRequested = false;

function scheduleReconnect() {
    if (reconnectTimeout) clearTimeout(reconnectTimeout);
    const delay = Math.min(30000, 1000 * Math.pow(2, reconnectAttempts));
    reconnectTimeout = setTimeout(() => { reconnectAttempts++; cleanSessionAndLaunch(); }, delay);
}
async function cleanSessionAndLaunch() {
    try {
        exec('pkill -9 -f "google-chrome" || true');
        const lockPath = path.join(AUTH_PATH, 'session', 'SingletonLock');
        if (fs.existsSync(lockPath)) fs.unlinkSync(lockPath);
    } catch (e) {}
    setTimeout(() => { try { launchBot(); } catch (err) { botStatus = "Error"; io.emit('connection_status', { connected: false, status: botStatus }); scheduleReconnect(); } }, 1000);
}
async function refreshContacts(force = false) {
    if (!isConnected || !client) return;
    try {
        const rawContacts = await client.getContacts();
        const validContactsMap = new Map();
        const results = await Promise.all(
            rawContacts.filter(c => c.isMyContact && c.isUser && !c.isGroup && !c.isMe)
                .map(async (c) => {
                    try {
                        const formatted = await c.getFormattedNumber();
                        if (formatted) {
                            const normalized = formatted.replace(/[^0-9]/g, '');
                            if (normalized.length >= 9 && normalized.length <= 15) {
                                return { number: normalized, name: (c.name || c.pushname || normalized).trim(), id: c.id._serialized };
                            }
                        }
                    } catch (e) {}
                    return null;
                })
        );
        results.forEach(c => { if (c && !validContactsMap.has(c.number)) validContactsMap.set(c.number, c); });
        const newContacts = Array.from(validContactsMap.values()).sort((a,b) => a.name.localeCompare(b.name));
        const newHash = JSON.stringify(newContacts.map(c => c.number + c.name));
        if (newHash !== contactsHash || force) {
            contacts = newContacts;
            contactsHash = newHash;
            io.emit('contacts_update', contacts);
            console.log(`📞 Contactos actualizados: ${contacts.length}`);
        }
    } catch (e) { console.error("❌ Error actualizando contactos:", e.message); }
}

function launchBot() {
    console.log('🔄 Iniciando bot...');
    const config = getConfig();
    messageQueue = new MessageQueue(config.queueInterval || 3000);
    client = new Client({
        authStrategy: new LocalAuth({ dataPath: AUTH_PATH }),
        webVersionCache: { 
            type: 'remote', 
            remotePath: 'https://raw.githubusercontent.com/wppconnect-team/wa-version/main/html/2.3000.1014590669-alpha.html' 
        },
        puppeteer: {
            executablePath: '/usr/bin/google-chrome-stable',
            headless: true,
            userAgent: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
            args: [
                '--no-sandbox',
                '--disable-setuid-sandbox',
                '--disable-dev-shm-usage',
                '--disable-gpu',
                '--no-first-run',
                '--disable-extensions',
                '--disable-background-timer-throttling',
                '--disable-backgrounding-occluded-windows',
                '--disable-renderer-backgrounding',
                '--disable-accelerated-2d-canvas',
                '--disable-software-rasterizer',
                '--js-flags="--max-old-space-size=64 --expose-gc"',
                '--disable-canvas-path-rendering',
                '--disable-accelerated-video-decode',
                '--disable-component-extensions-with-background-pages',
                '--disable-web-security',
                '--disable-features=IsolateOrigins,site-per-process',
                '--disable-threaded-animation',
                '--disable-threaded-scrolling',
                '--disable-ipc-flooding-protection'
            ],
            timeout: 120000
        }
    });
    client.on('pairing_code', (code) => { 
        io.emit('pairing_code', code); 
        pairingCodeRequested = false; 
        console.log('📱 Código de emparejamiento:', code); 
    });
    client.on('qr', (qr) => {
        botStatus = "Esperando QR"; 
        isConnected = false;
        console.log('📸 Generando QR...');
        qrcode.toDataURL(qr, (err, url) => {
            if (!err) {
                lastQRImage = url;
                io.emit('qr_update', url);
                console.log('✅ QR enviado al panel.');
            } else {
                console.error('❌ Error generando QR:', err);
            }
        });
        io.emit('connection_status', { connected: false, status: botStatus });
        reconnectAttempts = 0; 
        pairingCodeRequested = false;
    });
    client.on('ready', async () => {
        botStatus = "Conectado"; 
        isConnected = true; 
        lastQRImage = null; 
        reconnectAttempts = 0;
        io.emit('qr_clear'); 
        io.emit('connection_status', { connected: true, status: botStatus });
        console.log('✅ Conexión establecida.');
        setTimeout(async () => {
            await refreshContacts(true);
        }, 5000);
    });
    client.on('disconnected', () => {
        botStatus = "Desconectado"; 
        isConnected = false; 
        lastQRImage = null; 
        contacts = []; 
        contactsHash = '';
        io.emit('contacts_update', []); 
        io.emit('qr_clear'); 
        io.emit('connection_status', { connected: false, status: botStatus });
        console.log('⚠️ Desconectado, reconectando...');
        scheduleReconnect();
    });
    client.on('message', async (msg) => {
        try {
            if (msg.isGroup) return;
            if (msg.from === 'status@broadcast' || !msg.body) return;
            
            let senderNumber = null;
            try { const contact = await msg.getContact(); senderNumber = await contact.getFormattedNumber(); } catch (e) { senderNumber = normalizePhone(msg.from); }
            if (!senderNumber) return;
            let phone = senderNumber.replace(/[^0-9]/g, '');
            if (phone.length < 9 || phone.length > 15) return;
            
            const db = getDB();
            if (db.excluded.some(ex => phone.includes(ex.phone))) {
                console.log(`🚫 Mensaje de ${phone} ignorado (excluido)`);
                return;
            }
            const text = msg.body.toLowerCase().trim();
            console.log(`📩 Mensaje de ${phone}: "${text}"`);
            
            const trigger = db.training.find(t => text === t.key.toLowerCase().trim() || text.includes(t.key.toLowerCase().trim()));
            if (trigger) {
                console.log(`🎯 Trigger encontrado: "${trigger.key}" -> "${trigger.response}"`);
                const conf = getConfig();
                if (conf.responseDelay > 0) await new Promise(r => setTimeout(r, conf.responseDelay * 1000));
                if (trigger.mediaPaths && JSON.parse(trigger.mediaPaths).length > 0) {
                    const paths = JSON.parse(trigger.mediaPaths);
                    const absolutePaths = paths.map(p => {
                        const filename = path.basename(p);
                        return path.join(MEDIA_PATH, filename);
                    });
                    if (fs.existsSync(absolutePaths[0])) {
                        const media = MessageMedia.fromFilePath(absolutePaths[0]);
                        messageQueue.enqueue(msg.from, media, { caption: trigger.response });
                        for (let i = 1; i < absolutePaths.length; i++) {
                            if (fs.existsSync(absolutePaths[i])) {
                                const mediaExtra = MessageMedia.fromFilePath(absolutePaths[i]);
                                messageQueue.enqueue(msg.from, mediaExtra);
                            }
                        }
                    } else {
                        messageQueue.enqueue(msg.from, trigger.response);
                    }
                } else {
                    messageQueue.enqueue(msg.from, trigger.response);
                }
                updateStats(1, 0);
            } else {
                console.log(`ℹ️ No se encontró trigger para "${text}"`);
                updateStats(0, 1);
            }
        } catch (e) { console.error("⚠️ Error mensaje:", e.message); }
    });
    client.initialize().catch(e => {
        console.error("❌ Fallo crítico:", e.message);
        botStatus = "Error de inicio";
        io.emit('connection_status', { connected: false, status: botStatus });
        scheduleReconnect();
    });
}

// ===== RECORDATORIOS =====
const sentReminders = new Map();
setInterval(async () => {
    if (!isConnected) {
        console.log('⏳ Recordatorios: bot desconectado, esperando...');
        return;
    }
    const db = getDB();
    const currentRD = moment().tz(TZ).format('YYYY-MM-DDTHH:mm');
    let hasChanges = false;
    for (const rem of db.reminders) {
        if (rem.date === currentRD) {
            const key = `${rem.id}_${currentRD}`;
            const lastSent = sentReminders.get(key);
            if (!lastSent || (Date.now() - lastSent) > 60000) {
                const chatId = rem.phone.includes('@') ? rem.phone : `${rem.phone}@c.us`;
                console.log(`📨 Enviando recordatorio a ${chatId}: ${rem.message}`);
                const success = await sendMessage(chatId, rem.message, {}, 3);
                if (success) {
                    sentReminders.set(key, Date.now());
                    console.log(`✅ Recordatorio enviado a ${rem.phone}`);
                } else {
                    console.error(`❌ Falló envío de recordatorio a ${rem.phone}`);
                }
                if (rem.freq && rem.freq !== 'Una vez') {
                    let nextDate = moment.tz(rem.date, TZ);
                    if (rem.freq === 'Diario') nextDate.add(1, 'day');
                    else if (rem.freq === 'Semanal') nextDate.add(7, 'days');
                    else if (rem.freq === 'Mensual') nextDate.add(1, 'month');
                    else if (rem.freq === 'Anual') nextDate.add(1, 'year');
                    dbSqlite.prepare('UPDATE reminders SET date = ? WHERE id = ?').run(nextDate.format('YYYY-MM-DDTHH:mm'), rem.id);
                    hasChanges = true;
                } else {
                    dbSqlite.prepare('DELETE FROM reminders WHERE id = ?').run(rem.id);
                    hasChanges = true;
                }
            }
        }
    }
    if (hasChanges) { invalidateCache(); emitDataUpdate(); }
}, 30000);

// ===== BACKUP AUTOMÁTICO (con logs detallados) =====
let lastBackupDate = null;
function loadLastBackupDate() {
    try {
        const stats = dbSqlite.prepare('SELECT lastBackupDate FROM stats LIMIT 1').get();
        lastBackupDate = stats ? stats.lastBackupDate : null;
        console.log(`📅 Último backup: ${lastBackupDate || 'Nunca'}`);
    } catch (e) { lastBackupDate = null; }
}
loadLastBackupDate();

async function performBackup() {
    console.log('🔄 Iniciando proceso de backup automático...');
    const config = getConfig();
    const backupPhone = config.backupPhone;
    if (!backupPhone) {
        console.log('⚠️ Backup: no hay número de respaldo configurado.');
        return false;
    }
    if (!isConnected || !client) {
        console.log('⚠️ Backup: WhatsApp no conectado.');
        return false;
    }
    try {
        const data = {
            training: dbSqlite.prepare('SELECT * FROM training').all(),
            reminders: dbSqlite.prepare('SELECT * FROM reminders').all(),
            excluded: dbSqlite.prepare('SELECT * FROM excluded').all(),
            stats: dbSqlite.prepare('SELECT * FROM stats').all(),
            websites: dbSqlite.prepare('SELECT * FROM websites').all(),
            config: getConfig()
        };
        const backupPath = path.join(BACKUP_PATH, `backup_${Date.now()}.json`);
        fs.writeFileSync(backupPath, JSON.stringify(data, null, 2));
        console.log(`📄 Archivo de backup creado: ${backupPath}`);
        const media = MessageMedia.fromFilePath(backupPath);
        const chatId = backupPhone.includes('@') ? backupPhone : `${backupPhone}@c.us`;
        console.log(`📤 Enviando backup a ${chatId}...`);
        const success = await sendMessage(chatId, media, { caption: `GZMBOT BACKUP - ${moment().tz(TZ).format('DD/MM/YYYY hh:mm A')}` }, 3);
        fs.unlinkSync(backupPath);
        if (success) {
            const today = moment().tz(TZ).format('YYYY-MM-DD');
            dbSqlite.prepare('UPDATE stats SET lastBackupDate = ?').run(today);
            lastBackupDate = today;
            invalidateCache();
            emitDataUpdate();
            console.log('✅ Backup automático enviado correctamente.');
        } else {
            console.log('❌ Falló el envío del backup automático.');
        }
        return success;
    } catch (e) {
        console.error('❌ Error en backup automático:', e.message);
        return false;
    }
}

// Verificar cada minuto si es hora de backup
setInterval(async () => {
    const config = getConfig();
    const backupHour = config.backupHour || '12:00';
    const now = moment().tz(TZ);
    const currentTime = now.format('HH:mm');
    const today = now.format('YYYY-MM-DD');
    console.log(`⏰ Verificando hora: ${currentTime} (configurada: ${backupHour})`);
    if (currentTime === backupHour && lastBackupDate !== today) {
        console.log(`⏰ Hora de backup (${backupHour}), ejecutando...`);
        await performBackup();
        loadLastBackupDate();
    }
}, 60000);

setTimeout(() => {
    cleanSessionAndLaunch();
}, 2000);

io.on('connection', (socket) => {
    console.log('🔌 Cliente conectado al socket.');
    socket.emit('connection_status', { connected: isConnected, status: botStatus });
    if (lastQRImage) {
        console.log('📤 Enviando QR guardado al nuevo cliente.');
        socket.emit('qr_update', lastQRImage);
    }
    socket.emit('contacts_update', contacts);
    emitSystemStats();
    let intervalId = setInterval(() => { if (messageQueue && socket.connected) socket.emit('queue_size', messageQueue.size()); }, 60000);
    socket.on('force_refresh_contacts', async () => { await refreshContacts(true); });
    socket.on('disconnect', () => clearInterval(intervalId));
});

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
    const fc = getConfig();
    const db = getDB();
    const websitesWithContent = db.websites.map(w => {
        let content = w.content || '';
        if (content.endsWith('.html')) {
            const filePath = path.join(WORKERS_PATH, content);
            try {
                if (fs.existsSync(filePath)) {
                    content = fs.readFileSync(filePath, 'utf8');
                }
            } catch (e) {}
        }
        return { ...w, content };
    });
    res.json({
        ...db,
        websites: websitesWithContent,
        botStatus,
        qrImage: lastQRImage,
        isConnected,
        backupPhone: fc.backupPhone || '',
        backupHour: fc.backupHour || '12:00',
        responseDelay: fc.responseDelay || 0,
        queueInterval: fc.queueInterval || 3000,
        queueSize: messageQueue ? messageQueue.size() : 0,
        serverTime: moment().tz(TZ).format('DD/MM/YYYY hh:mm:ss A'),
        timezone: TZ
    });
});

app.get('/api/contacts', checkAuth, (req, res) => res.json(contacts));

app.post('/api/pairing', checkAuth, async (req, res) => {
    const { phone } = req.body;
    if (!phone || !client || isConnected || pairingCodeRequested) {
        return res.status(400).json({ ok: false, error: 'Solicitud inválida' });
    }
    try {
        pairingCodeRequested = true;
        const cleanPhone = phone.replace(/[^0-9]/g, '');
        if (cleanPhone.length < 9 || cleanPhone.length > 15) { pairingCodeRequested = false; return res.status(400).json({ ok: false, error: 'Número inválido' }); }
        const code = await client.requestPairingCode(cleanPhone);
        io.emit('pairing_code', code);
        pairingCodeRequested = false;
        res.json({ ok: true, code });
    } catch (error) {
        pairingCodeRequested = false;
        res.status(500).json({ ok: false, error: error.message });
    }
});

// ===== CRUD Workers =====
app.get('/api/websites', checkAuth, (req, res) => {
    const db = getDB();
    const websitesWithContent = db.websites.map(w => {
        let content = w.content || '';
        if (content.endsWith('.html')) {
            const filePath = path.join(WORKERS_PATH, content);
            try {
                if (fs.existsSync(filePath)) {
                    content = fs.readFileSync(filePath, 'utf8');
                }
            } catch (e) {}
        }
        return { ...w, content };
    });
    res.json(websitesWithContent);
});

app.post('/api/websites', checkAuth, async (req, res) => {
    try {
        let { name, slug, content } = req.body;
        if (!name || !content) return res.status(400).json({ ok: false, error: 'Faltan campos' });
        if (slug) slug = slug.trim().toLowerCase().replace(/\s+/g, '-').replace(/[^a-z0-9-]/g, '');
        if (!slug) {
            slug = name.trim().toLowerCase().replace(/\s+/g, '-').replace(/[^a-z0-9-]/g, '');
            if (!slug) slug = 'site-' + Date.now();
        }
        const exists = dbSqlite.prepare('SELECT id FROM websites WHERE slug = ?').get(slug);
        if (exists) return res.status(400).json({ ok: false, error: 'Slug ya existe' });
        const filePath = path.join(WORKERS_PATH, slug + '.html');
        await fsPromises.writeFile(filePath, content, 'utf8');
        await fsPromises.chmod(filePath, 0o644);
        dbSqlite.prepare('INSERT INTO websites (name, slug, content) VALUES (?, ?, ?)').run(name, slug, slug + '.html');
        invalidateCache();
        emitDataUpdate();
        res.json({ ok: true });
    } catch (err) {
        console.error('Error en POST /api/websites:', err);
        res.status(500).json({ ok: false, error: err.message });
    }
});

app.put('/api/websites/:id', checkAuth, async (req, res) => {
    try {
        const { id } = req.params;
        let { name, slug, content } = req.body;
        if (!name || !content) return res.status(400).json({ ok: false, error: 'Faltan campos' });
        if (slug) slug = slug.trim().toLowerCase().replace(/\s+/g, '-').replace(/[^a-z0-9-]/g, '');
        if (!slug) {
            slug = name.trim().toLowerCase().replace(/\s+/g, '-').replace(/[^a-z0-9-]/g, '');
            if (!slug) slug = 'site-' + Date.now();
        }
        const exists = dbSqlite.prepare('SELECT id FROM websites WHERE slug = ? AND id != ?').get(slug, id);
        if (exists) return res.status(400).json({ ok: false, error: 'Slug ya existe' });
        const old = dbSqlite.prepare('SELECT slug FROM websites WHERE id = ?').get(id);
        if (old && old.slug !== slug) {
            const oldPath = path.join(WORKERS_PATH, old.slug + '.html');
            if (fs.existsSync(oldPath)) await fsPromises.unlink(oldPath);
        }
        const filePath = path.join(WORKERS_PATH, slug + '.html');
        await fsPromises.writeFile(filePath, content, 'utf8');
        await fsPromises.chmod(filePath, 0o644);
        dbSqlite.prepare(`UPDATE websites SET name = ?, slug = ?, content = ?, updated_at = datetime('now', 'localtime') WHERE id = ?`)
            .run(name, slug, slug + '.html', id);
        invalidateCache();
        emitDataUpdate();
        res.json({ ok: true });
    } catch (err) {
        console.error('Error en PUT /api/websites:', err);
        res.status(500).json({ ok: false, error: err.message });
    }
});

app.delete('/api/websites/:id', checkAuth, async (req, res) => {
    try {
        const { id } = req.params;
        const site = dbSqlite.prepare('SELECT slug FROM websites WHERE id = ?').get(id);
        if (site) {
            const filePath = path.join(WORKERS_PATH, site.slug + '.html');
            if (fs.existsSync(filePath)) await fsPromises.unlink(filePath);
        }
        dbSqlite.prepare('DELETE FROM websites WHERE id = ?').run(id);
        invalidateCache();
        emitDataUpdate();
        res.json({ ok: true });
    } catch (err) { res.status(500).json({ ok: false, error: err.message }); }
});

app.get('/:slug', (req, res) => {
    const slug = req.params.slug;
    if (['login','api','socket.io','media','favicon.ico'].includes(slug)) return res.status(404).send('Not found');
    const cleanSlug = slug.replace(/[^a-z0-9-]/g, '');
    if (cleanSlug !== slug) return res.status(400).send('Slug inválido');
    const filePath = path.join(WORKERS_PATH, cleanSlug + '.html');
    if (fs.existsSync(filePath)) res.sendFile(filePath);
    else res.status(404).send('Sitio no encontrado');
});

// ===== Entrenamiento =====
app.post('/api/train', checkAuth, upload.array('media'), async (req, res) => {
    try {
        const { id, key, response, existingMedia } = req.body;
        let paths = [];
        let types = [];

        if (existingMedia) {
            try {
                const parsed = JSON.parse(existingMedia);
                parsed.forEach(p => {
                    paths.push(p);
                    if (p.match(/\.(mp4|3gp|avi|mov)$/i)) types.push('video/mp4');
                    else types.push('image/jpeg');
                });
            } catch (e) {}
        }

        if (req.files && req.files.length > 0) {
            req.files.forEach(file => {
                const relativePath = '/media/' + file.filename;
                paths.push(relativePath);
                types.push(file.mimetype);
            });
        }

        if (id) {
            const oldRule = dbSqlite.prepare('SELECT mediaPaths FROM training WHERE id = ?').get(id);
            if (oldRule && oldRule.mediaPaths) {
                try {
                    const oldPaths = JSON.parse(oldRule.mediaPaths);
                    for (const oldP of oldPaths) {
                        if (!paths.includes(oldP)) {
                            const filename = path.basename(oldP);
                            const diskPath = path.join(MEDIA_PATH, filename);
                            if (fs.existsSync(diskPath)) await fsPromises.unlink(diskPath);
                        }
                    }
                } catch (e) {}
            }
            dbSqlite.prepare('UPDATE training SET key = ?, response = ?, mediaPaths = ?, mediaTypes = ? WHERE id = ?')
                .run(key, response, JSON.stringify(paths), JSON.stringify(types), id);
        } else {
            dbSqlite.prepare('INSERT INTO training (key, response, mediaPaths, mediaTypes) VALUES (?, ?, ?, ?)')
                .run(key, response, JSON.stringify(paths), JSON.stringify(types));
        }

        invalidateCache();
        emitDataUpdate();
        res.json({ ok: true });
    } catch (err) {
        console.error('Error en /api/train:', err);
        res.status(500).json({ ok: false, error: 'Error al guardar: ' + err.message });
    }
});

app.delete('/api/train/:id', checkAuth, async (req, res) => {
    try {
        const id = req.params.id;
        const rule = dbSqlite.prepare('SELECT mediaPaths FROM training WHERE id = ?').get(id);
        if (rule && rule.mediaPaths) {
            try {
                const paths = JSON.parse(rule.mediaPaths);
                for (const p of paths) {
                    const filename = path.basename(p);
                    const diskPath = path.join(MEDIA_PATH, filename);
                    if (fs.existsSync(diskPath)) await fsPromises.unlink(diskPath);
                }
            } catch (e) {}
        }
        dbSqlite.prepare('DELETE FROM training WHERE id = ?').run(id);
        invalidateCache();
        emitDataUpdate();
        res.json({ ok: true });
    } catch (err) {
        res.status(500).json({ ok: false, error: err.message });
    }
});

// ===== Recordatorios (API) =====
app.post('/api/reminders', checkAuth, (req, res) => {
    const { id, name, phone, message, freq, date } = req.body;
    if (id) {
        dbSqlite.prepare('UPDATE reminders SET name = ?, phone = ?, message = ?, freq = ?, date = ? WHERE id = ?')
            .run(name, phone, message, freq, date, id);
    } else {
        dbSqlite.prepare('INSERT INTO reminders (name, phone, message, freq, date) VALUES (?, ?, ?, ?, ?)')
            .run(name, phone, message, freq, date);
    }
    invalidateCache();
    emitDataUpdate();
    res.json({ ok: true });
});

app.delete('/api/reminders/:id', checkAuth, (req, res) => {
    dbSqlite.prepare('DELETE FROM reminders WHERE id = ?').run(req.params.id);
    invalidateCache();
    emitDataUpdate();
    res.json({ ok: true });
});

// ===== Excluidos =====
app.post('/api/exclude', checkAuth, (req, res) => {
    dbSqlite.prepare('INSERT INTO excluded (name, phone) VALUES (?, ?)').run(req.body.name, req.body.phone);
    invalidateCache();
    emitDataUpdate();
    res.json({ ok: true });
});

app.delete('/api/exclude/:id', checkAuth, (req, res) => {
    dbSqlite.prepare('DELETE FROM excluded WHERE id = ?').run(req.params.id);
    invalidateCache();
    emitDataUpdate();
    res.json({ ok: true });
});

// ===== Configuración =====
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
    res.json({ ok: true });
});
app.post('/api/config/backup-hour', checkAuth, (req, res) => {
    const fc = getConfig();
    fc.backupHour = req.body.backupHour || '12:00';
    fs.writeFileSync(CONFIG_PATH, JSON.stringify(fc, null, 2));
    res.json({ ok: true });
});
app.post('/api/config/delay', checkAuth, (req, res) => {
    const fc = getConfig();
    fc.responseDelay = parseFloat(req.body.delay) || 0;
    fs.writeFileSync(CONFIG_PATH, JSON.stringify(fc, null, 2));
    res.json({ ok: true });
});
app.post('/api/config/queue-interval', checkAuth, (req, res) => {
    const fc = getConfig();
    fc.queueInterval = parseInt(req.body.interval) || 3000;
    fs.writeFileSync(CONFIG_PATH, JSON.stringify(fc, null, 2));
    if (messageQueue) messageQueue.setInterval(fc.queueInterval);
    res.json({ ok: true });
});
app.post('/api/logout-wa', checkAuth, async (req, res) => {
    try {
        if (client) { await client.logout().catch(()=>{}); await client.destroy().catch(()=>{}); }
        cleanSessionAndLaunch();
        res.json({ ok: true });
    } catch (e) { res.status(500).json({ ok: false, error: e.message }); }
});

// ===== Backup (manual y automático) =====
app.get('/api/backup/download', checkAuth, (req, res) => {
    try {
        const data = {
            training: dbSqlite.prepare('SELECT * FROM training').all(),
            reminders: dbSqlite.prepare('SELECT * FROM reminders').all(),
            excluded: dbSqlite.prepare('SELECT * FROM excluded').all(),
            stats: dbSqlite.prepare('SELECT * FROM stats').all(),
            websites: dbSqlite.prepare('SELECT * FROM websites').all(),
            config: getConfig()
        };
        const backupPath = path.join(BACKUP_PATH, `backup_${Date.now()}.json`);
        fs.writeFileSync(backupPath, JSON.stringify(data, null, 2));
        res.download(backupPath, 'gzmbot_backup.json', (err) => { if (err) console.error(err); fs.unlinkSync(backupPath); });
    } catch (e) { res.status(500).json({ error: e.message }); }
});

app.post('/api/backup/restore', checkAuth, upload.single('backup'), async (req, res) => {
    try {
        const backupData = JSON.parse(fs.readFileSync(req.file.path, 'utf8'));
        if (backupData.training && backupData.reminders && backupData.excluded && backupData.stats && backupData.websites !== undefined) {
            dbSqlite.prepare('DELETE FROM training').run();
            dbSqlite.prepare('DELETE FROM reminders').run();
            dbSqlite.prepare('DELETE FROM excluded').run();
            dbSqlite.prepare('DELETE FROM stats').run();
            dbSqlite.prepare('DELETE FROM websites').run();
            
            const insertTrain = dbSqlite.prepare('INSERT INTO training (id, key, response, mediaPaths, mediaTypes) VALUES (?, ?, ?, ?, ?)');
            backupData.training.forEach(t => insertTrain.run(t.id, t.key, t.response, t.mediaPaths, t.mediaTypes));
            dbSqlite.prepare("UPDATE sqlite_sequence SET seq = (SELECT MAX(id) FROM training) WHERE name = 'training'").run();
            
            const insertRem = dbSqlite.prepare('INSERT INTO reminders (id, name, phone, message, freq, date) VALUES (?, ?, ?, ?, ?, ?)');
            backupData.reminders.forEach(r => insertRem.run(r.id, r.name, r.phone, r.message, r.freq, r.date));
            dbSqlite.prepare("UPDATE sqlite_sequence SET seq = (SELECT MAX(id) FROM reminders) WHERE name = 'reminders'").run();
            
            const insertExc = dbSqlite.prepare('INSERT INTO excluded (id, name, phone) VALUES (?, ?, ?)');
            backupData.excluded.forEach(e => insertExc.run(e.id, e.name, e.phone));
            dbSqlite.prepare("UPDATE sqlite_sequence SET seq = (SELECT MAX(id) FROM excluded) WHERE name = 'excluded'").run();
            
            const insertStats = dbSqlite.prepare('INSERT INTO stats (id, replied, total, lastBackupDate) VALUES (?, ?, ?, ?)');
            backupData.stats.forEach(s => insertStats.run(s.id, s.replied, s.total, s.lastBackupDate || null));
            
            const insertWeb = dbSqlite.prepare('INSERT INTO websites (id, name, slug, content, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)');
            for (const w of backupData.websites) {
                const filePath = path.join(WORKERS_PATH, w.slug + '.html');
                await fsPromises.writeFile(filePath, '<!-- Contenido restaurado -->', 'utf8');
                await fsPromises.chmod(filePath, 0o644);
                insertWeb.run(w.id, w.name, w.slug, w.slug + '.html', w.created_at, w.updated_at);
            }
            dbSqlite.prepare("UPDATE sqlite_sequence SET seq = (SELECT MAX(id) FROM websites) WHERE name = 'websites'").run();
            
            invalidateCache();
            emitDataUpdate();
            res.json({ ok: true });
        } else { res.status(400).json({ ok: false, error: 'Formato incompatible' }); }
        await fsPromises.unlink(req.file.path);
    } catch (e) { res.status(500).json({ ok: false, error: e.message }); }
});

app.post('/api/backup/send', checkAuth, async (req, res) => {
    try {
        const backupPhone = getConfig().backupPhone;
        if (!backupPhone) return res.json({ ok: false, error: 'Teléfono backup no especificado' });
        const data = {
            training: dbSqlite.prepare('SELECT * FROM training').all(),
            reminders: dbSqlite.prepare('SELECT * FROM reminders').all(),
            excluded: dbSqlite.prepare('SELECT * FROM excluded').all(),
            stats: dbSqlite.prepare('SELECT * FROM stats').all(),
            websites: dbSqlite.prepare('SELECT * FROM websites').all(),
            config: getConfig()
        };
        const backupPath = path.join(BACKUP_PATH, `backup_${Date.now()}.json`);
        fs.writeFileSync(backupPath, JSON.stringify(data, null, 2));
        if (isConnected && client) {
            const media = MessageMedia.fromFilePath(backupPath);
            const chatId = backupPhone.includes('@') ? backupPhone : `${backupPhone}@c.us`;
            const success = await sendMessage(chatId, media, { caption: `GZMBOT BACKUP - ${moment().tz(TZ).format('DD/MM/YYYY hh:mm A')}` }, 3);
            res.json({ ok: success });
        } else { res.json({ ok: false, error: 'WhatsApp no conectado' }); }
        fs.unlinkSync(backupPath);
    } catch (e) { res.status(500).json({ ok: false, error: e.message }); }
});

app.get('/api/train/template', checkAuth, (req, res) => {
    const header = 'PALABRAS_CLAVE,RESPUESTA\n';
    const example = '"hola,buenas","¡Hola! ¿En qué puedo ayudarte?"\n';
    res.setHeader('Content-Type', 'text/csv');
    res.setHeader('Content-Disposition', 'attachment; filename=plantilla_entrenamiento.csv');
    res.send(header + example);
});

app.post('/api/train/import', checkAuth, upload.single('file'), (req, res) => {
    try {
        const content = fs.readFileSync(req.file.path, 'utf8');
        const lines = content.split('\n');
        let imported = 0;
        for (let i = 1; i < lines.length; i++) {
            const line = lines[i].trim();
            if (line === '') continue;
            const firstComma = line.indexOf(',');
            if (firstComma === -1) continue;
            let key = line.substring(0, firstComma).replace(/^"|"$/g, '').trim();
            let response = line.substring(firstComma + 1).replace(/^"|"$/g, '').trim();
            if (key && response) {
                dbSqlite.prepare('INSERT INTO training (key, response, mediaPaths, mediaTypes) VALUES (?, ?, ?, ?)')
                    .run(key, response, '[]', '[]');
                imported++;
            }
        }
        invalidateCache();
        emitDataUpdate();
        res.json({ ok: true, imported });
        fs.unlinkSync(req.file.path);
    } catch (e) { res.status(500).json({ ok: false, error: e.message }); }
});

APPEOF

# ============================================================
# 9. index.html (frontend con persistencia de hora)
# ============================================================
echo "🎨 Generando frontend (index.html)..."
cat <<'HTMLEOF' > views/index.html
<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
    <title>GZMBOT | Panel Admin</title>
    <script src="https://cdn.tailwindcss.com"></script>
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600;700;800;900&family=Outfit:wght@400;600;700;800;900&display=swap" rel="stylesheet">
    <script src="https://unpkg.com/lucide@latest"></script>
    <script src="/socket.io/socket.io.js"></script>
    <style>
        :root { --bg-primary: #0c0c12; --green-light: #6ee7b7; --green-medium: #34d399; --green-dark: #10b981; --glass-bg: rgba(12,12,18,0.75); --glass-border: rgba(52,211,153,0.2); }
        * { margin:0; padding:0; box-sizing:border-box; }
        body { background: var(--bg-primary); color: #f3f4f6; font-family: 'Inter', sans-serif; overflow-x:hidden; position:relative; min-height:100vh; }
        .bg-waves { position:fixed; inset:0; z-index:-1; background:var(--bg-primary); overflow:hidden; }
        .wave { position:absolute; border-radius:50%; background:radial-gradient(circle, rgba(110,231,183,0.25) 0%, transparent 70%); animation:waveMove 22s infinite ease-in-out alternate; width:900px; height:900px; top:-250px; left:-250px; filter:blur(30px); }
        .wave:nth-child(2) { width:1100px; height:1100px; top:auto; bottom:-350px; right:-350px; animation-duration:28s; animation-delay:-6s; background:radial-gradient(circle, rgba(52,211,153,0.20) 0%, transparent 70%); filter:blur(40px); }
        .wave:nth-child(3) { width:700px; height:700px; top:50%; left:50%; transform:translate(-50%,-50%); animation-duration:32s; animation-delay:-12s; background:radial-gradient(circle, rgba(110,231,183,0.15) 0%, transparent 70%); filter:blur(35px); }
        @keyframes waveMove { 0% { transform:translate(0,0) scale(1); } 33% { transform:translate(100px,-80px) scale(1.15); } 66% { transform:translate(-60px,100px) scale(0.85); } 100% { transform:translate(80px,-60px) scale(1.05); } }
        .glass-panel { background:var(--glass-bg); backdrop-filter:blur(28px) saturate(200%); border:1px solid var(--glass-border); }
        .glass-card { background:rgba(20,20,30,0.5); border:1px solid rgba(52,211,153,0.08); transition:all .4s cubic-bezier(.4,0,.2,1); border-radius:1.5rem; }
        .glass-card:hover { border-color:rgba(52,211,153,0.3); box-shadow:0 12px 40px -12px rgba(52,211,153,0.15); transform:translateY(-3px); }
        .page { display:none; animation:fadeIn .5s cubic-bezier(.16,1,.3,1) forwards; }
        .page.active { display:block; }
        @keyframes fadeIn { from { opacity:0; transform:translateY(14px) scale(0.98); } to { opacity:1; transform:translateY(0) scale(1); } }
        input, select, textarea { background:rgba(0,0,0,0.5)!important; border:1px solid rgba(52,211,153,0.15)!important; color:#fff!important; padding:13px 18px!important; border-radius:18px!important; outline:none; width:100%; font-size:14px; box-sizing:border-box; transition:border .3s, box-shadow .3s; }
        input:focus, textarea:focus, select:focus { border-color:var(--green-medium)!important; box-shadow:0 0 0 4px rgba(52,211,153,0.1); }
        input[type="datetime-local"] { padding:13px 18px !important; border:1px solid rgba(52,211,153,0.15) !important; border-radius:18px !important; background:rgba(0,0,0,0.5) !important; color:#fff !important; width:100%; box-sizing:border-box; appearance:none; -webkit-appearance:none; }
        input[type="datetime-local"]:focus { border-color:var(--green-medium) !important; box-shadow:0 0 0 4px rgba(52,211,153,0.1) !important; }
        input[type="time"] { padding:13px 18px !important; border:1px solid rgba(52,211,153,0.15) !important; border-radius:18px !important; background:rgba(0,0,0,0.5) !important; color:#fff !important; width:100%; box-sizing:border-box; appearance:none; -webkit-appearance:none; }
        input[type="time"]:focus { border-color:var(--green-medium) !important; box-shadow:0 0 0 4px rgba(52,211,153,0.1) !important; }
        .media-type-btn { padding:9px 20px; border-radius:14px; cursor:pointer; font-size:13px; font-weight:500; transition:all .2s; }
        .media-type-btn.active { background:rgba(52,211,153,0.15); border-color:var(--green-medium); color:var(--green-medium); box-shadow:0 0 20px rgba(52,211,153,0.05); }
        .media-type-btn:not(.active) { background:rgba(255,255,255,0.03); border:1px solid rgba(255,255,255,0.06); color:#9ca3af; }
        .media-type-btn:not(.active):hover { background:rgba(52,211,153,0.06); }
        input[type="range"] { -webkit-appearance:none; appearance:none; height:6px; border-radius:999px; background:#1a1a24; outline:none; }
        input[type="range"]::-webkit-slider-thumb { -webkit-appearance:none; width:18px; height:18px; border-radius:50%; background:var(--green-medium); cursor:pointer; box-shadow:0 0 12px rgba(52,211,153,0.5); }
        .modal { display:none; position:fixed; inset:0; background:rgba(0,0,0,0.8); backdrop-filter:blur(8px); z-index:1000; align-items:center; justify-content:center; }
        .modal.active { display:flex; }
        .modal-content { background:#12121e; border:1px solid rgba(52,211,153,0.12); border-radius:2rem; width:90%; max-width:800px; max-height:90vh; overflow-y:auto; padding:1.5rem; }
        .contact-item { padding:.75rem; border-bottom:1px solid rgba(52,211,153,0.05); cursor:pointer; transition:.2s; border-radius:1rem; }
        .contact-item:hover { background:rgba(52,211,153,0.1); }
        .btn-green { background:linear-gradient(135deg, #0d9488 0%, #10b981 50%, #34d399 100%) !important; box-shadow:0 8px 30px -6px rgba(52,211,153,0.25); transition:all 0.3s cubic-bezier(0.4,0,0.2,1); color:#fff !important; border:none; font-weight:700; }
        .btn-green:hover { transform:translateY(-2px); box-shadow:0 14px 38px -4px rgba(52,211,153,0.4); filter:brightness(1.05); color:#fff !important; }
        .btn-green:active { transform:translateY(1px); }
        .btn-red-solid { background:#ef4444 !important; box-shadow:0 8px 30px -6px rgba(239,68,68,0.3); transition:all 0.3s cubic-bezier(0.4,0,0.2,1); color:#fff !important; border:none; font-weight:700; }
        .btn-red-solid:hover { transform:translateY(-2px); box-shadow:0 14px 38px -4px rgba(239,68,68,0.5); filter:brightness(1.05); color:#fff !important; }
        .btn-red-solid:active { transform:translateY(1px); }
        .qr-wrapper { background:#0a0a12; border-radius:2rem; padding:1.5rem; border:1px solid rgba(52,211,153,0.2); box-shadow:0 0 40px rgba(52,211,153,0.04); display:inline-block; }
        .toast-container { position:fixed; bottom:1.5rem; right:1.5rem; z-index:9999; display:flex; flex-direction:column; gap:0.75rem; max-width:380px; pointer-events:none; }
        .toast { background:rgba(12,12,18,0.92); backdrop-filter:blur(12px); border:1px solid rgba(52,211,153,0.12); border-radius:1rem; padding:1rem 1.25rem; box-shadow:0 12px 40px rgba(0,0,0,0.6); display:flex; align-items:flex-start; gap:0.75rem; transform:translateY(20px); opacity:0; transition:all .3s cubic-bezier(.4,0,.2,1); pointer-events:auto; }
        .toast.show { opacity:1; transform:translateY(0); }
        .toast-icon { background:rgba(52,211,153,0.08); border-radius:0.75rem; padding:0.5rem; color:var(--green-medium); flex-shrink:0; }
        .toast-success .toast-icon { background:rgba(52,211,153,0.1); color:var(--green-medium); }
        .toast-error .toast-icon { background:rgba(239,68,68,0.1); color:#f87171; }
        .toast-warning .toast-icon { background:rgba(245,158,11,0.1); color:#fbbf24; }
        .toast-body { flex:1; }
        .toast-title { font-size:0.75rem; font-weight:700; color:#fff; text-transform:uppercase; letter-spacing:0.05em; }
        .toast-message { font-size:0.8rem; color:#d1d5db; margin-top:0.15rem; line-height:1.4; }
        .toast-close { background:transparent; border:none; color:#6b7280; cursor:pointer; padding:0.25rem; transition:color .2s; }
        .toast-close:hover { color:#fff; }
        .connected-message { display:none; flex-direction:column; align-items:center; justify-content:center; padding:1.5rem 0; }
        .connection-toggle-btn { background:rgba(52,211,153,0.06); border:1px solid rgba(52,211,153,0.15); color:#ffffff; transition:all .3s; }
        .connection-toggle-btn:hover { background:rgba(52,211,153,0.12); border-color:var(--green-medium); color:#fff; }
        .copy-btn { background:rgba(255,255,255,0.03); border:1px solid rgba(255,255,255,0.06); color:#9ca3af; transition:all .2s; }
        .copy-btn:hover { background:rgba(52,211,153,0.06); color:#ffffff; }
        .contact-select-btn { background:rgba(52,211,153,0.08); border:1px solid rgba(52,211,153,0.15); color:#ffffff; }
        .contact-select-btn:hover { background:rgba(52,211,153,0.15); color:#fff; }
        .code-editor { font-family:'Courier New',monospace; font-size:13px; line-height:1.5; tab-size:2; min-height:300px; }
        .code-editor:focus { outline:none; border-color:var(--green-medium); box-shadow:0 0 0 4px rgba(52,211,153,0.06); }
        .website-card { transition:all 0.3s; }
        .website-card:hover { border-color:rgba(52,211,153,0.2); transform:translateY(-2px); }
        .header-island { position:fixed; top:12px; left:50%; transform:translateX(-50%); width:calc(100% - 40px); max-width:1400px; z-index:40; background:rgba(12,12,18,0.6); backdrop-filter:blur(24px) saturate(200%); border:1px solid rgba(52,211,153,0.08); border-radius:999px; padding:6px 16px; display:flex; align-items:center; justify-content:space-between; box-shadow:0 8px 32px rgba(0,0,0,0.5), inset 0 1px 0 rgba(52,211,153,0.04); transition:all 0.3s ease; height:56px; }
        .header-island:hover { background:rgba(12,12,18,0.8); border-color:rgba(52,211,153,0.12); }
        .header-island .brand { display:flex; align-items:center; gap:8px; }
        .header-island .brand .logo-icon { color:var(--green-medium); }
        .header-island .brand .logo-text { font-size:18px; font-weight:900; font-family:'Outfit',sans-serif; color:#ffffff; }
        .header-island .right-group { display:flex; align-items:center; gap:12px; }
        .header-island .clock { font-size:12px; font-weight:500; color:#ffffff; background:rgba(52,211,153,0.04); padding:4px 12px; border-radius:999px; border:1px solid rgba(52,211,153,0.06); cursor:pointer; user-select:none; transition:background .2s; }
        .header-island .clock:hover { background:rgba(52,211,153,0.08); }
        .header-island .clock .date { font-size:9px; color:#6b7280; font-weight:400; margin-left:6px; }
        .menu-btn { background:rgba(52,211,153,0.06); border:1px solid rgba(52,211,153,0.08); color:#ffffff; cursor:pointer; width:40px; height:40px; border-radius:50%; display:flex; align-items:center; justify-content:center; transition:all 0.3s; }
        .menu-btn:hover { background:rgba(52,211,153,0.12); border-color:var(--green-medium); color:#fff; box-shadow:0 0 20px rgba(52,211,153,0.05); }
        .menu-btn i { width:22px; height:22px; color:#ffffff; }
        .dropdown-menu { display:none; position:fixed; top:72px; left:50%; transform:translateX(-50%); width:calc(100% - 40px); max-width:520px; background:rgba(12,12,18,0.92); backdrop-filter:blur(32px) saturate(200%); border:1px solid rgba(52,211,153,0.08); border-radius:28px; padding:10px 6px; box-shadow:0 24px 64px rgba(0,0,0,0.8), inset 0 1px 0 rgba(52,211,153,0.03); z-index:45; animation:dropdownFade 0.3s cubic-bezier(.16,1,.3,1); }
        .dropdown-menu.open { display:block; }
        @keyframes dropdownFade { from { opacity:0; transform:translateX(-50%) scale(0.95) translateY(-8px); } to { opacity:1; transform:translateX(-50%) scale(1) translateY(0); } }
        .dropdown-menu .menu-item { display:flex; align-items:center; gap:14px; padding:12px 18px; border-radius:16px; color:#d1d5db; font-weight:500; font-size:14px; transition:all 0.2s; cursor:pointer; border:none; background:transparent; width:100%; text-align:left; }
        .dropdown-menu .menu-item:hover { background:rgba(52,211,153,0.06); color:#ffffff; }
        .dropdown-menu .menu-item.active { background:rgba(52,211,153,0.08); color:#ffffff; border-left:3px solid var(--green-medium); }
        .dropdown-menu .menu-item i { width:20px; height:20px; flex-shrink:0; color:#ffffff; }
        .dropdown-menu .menu-divider { height:1px; background:rgba(52,211,153,0.04); margin:6px 12px; }
        .dropdown-menu .menu-footer { padding:8px 16px 4px; color:#4b5563; font-size:9px; text-align:center; border-top:1px solid rgba(52,211,153,0.03); margin-top:4px; }
        .menu-overlay { display:none; position:fixed; inset:0; background:rgba(0,0,0,0.5); backdrop-filter:blur(8px); z-index:44; }
        .menu-overlay.active { display:block; }
        .status-badge { display:inline-flex; align-items:center; gap:8px; padding:6px 16px 6px 12px; border-radius:999px; font-size:11px; font-weight:600; letter-spacing:0.5px; text-transform:uppercase; border:1px solid rgba(239,68,68,0.1); background:rgba(239,68,68,0.05); color:#ffffff; transition:all 0.4s ease; }
        .status-badge .dot { width:10px; height:10px; border-radius:50%; background:#ef4444; transition:all 0.4s ease; }
        .status-badge.connected { background:rgba(52,211,153,0.06); color:#ffffff; border-color:rgba(52,211,153,0.12); }
        .status-badge.connected .dot { background:var(--green-medium); animation:pulse-dot 2s infinite; }
        @keyframes pulse-dot { 0% { box-shadow:0 0 0 0 rgba(52,211,153,0.4); } 70% { box-shadow:0 0 0 8px rgba(52,211,153,0); } 100% { box-shadow:0 0 0 0 rgba(52,211,153,0); } }
        .media-preview-item { position:relative; display:inline-block; margin:4px; }
        .media-preview-item img, .media-preview-item video { width:80px; height:80px; object-fit:cover; border-radius:12px; border:1px solid rgba(52,211,153,0.06); }
        .media-preview-item .remove-media { position:absolute; top:-6px; right:-6px; width:22px; height:22px; border-radius:50%; background:rgba(239,68,68,0.8); border:none; color:white; font-size:12px; cursor:pointer; display:flex; align-items:center; justify-content:center; transition:all 0.2s; }
        .media-preview-item .remove-media:hover { transform:scale(1.15); background:#ef4444; }
        .performance-bar { height:8px; border-radius:999px; background:#1a1a24; overflow:hidden; width:100%; margin-top:6px; }
        .performance-bar .fill { height:100%; border-radius:999px; transition:width 0.5s ease; }
        @media (max-width:640px) { .header-island { width:calc(100% - 20px); padding:4px 10px; top:8px; border-radius:20px; height:48px; } .header-island .brand .logo-text { font-size:15px; } .header-island .clock { font-size:10px; padding:2px 8px; } .header-island .clock .date { display:none; } .dropdown-menu { top:62px; width:calc(100% - 20px); border-radius:20px; } #main-content { padding-top:64px; } .menu-btn { width:34px; height:34px; } }
        #main-content { padding-top:76px; }
    </style>
</head>
<body>
    <div class="bg-waves"><div class="wave"></div><div class="wave"></div><div class="wave"></div></div>
    <div class="menu-overlay" id="menuOverlay" onclick="closeMenu()"></div>
    <div class="toast-container" id="toastContainer"></div>
    <!-- Contact Modal -->
    <div id="contactModal" class="modal">
        <div class="modal-content">
            <div class="flex justify-between items-center mb-4">
                <h3 class="text-lg font-bold text-white">Seleccionar contacto</h3>
                <button onclick="closeContactModal()" class="text-zinc-400 hover:text-white"><i data-lucide="x" class="w-5 h-5"></i></button>
            </div>
            <input type="text" id="contactSearch" placeholder="Buscar por nombre o número..." class="mb-4 text-sm">
            <div id="contactList" class="space-y-2 max-h-96 overflow-y-auto">
                <div class="text-center py-4 text-zinc-500">Cargando contactos...</div>
            </div>
            <div class="mt-4 text-center text-xs text-zinc-500">O escribe el número manualmente en el campo</div>
        </div>
    </div>
    <!-- Website Modal -->
    <div id="websiteModal" class="modal">
        <div class="modal-content" style="max-width:800px; max-height:90vh;">
            <div class="flex justify-between items-center mb-4">
                <h3 class="text-lg font-bold text-white" id="website-modal-title">Crear sitio web</h3>
                <button onclick="closeWebsiteModal()" class="text-zinc-400 hover:text-white"><i data-lucide="x" class="w-5 h-5"></i></button>
            </div>
            <div class="space-y-4">
                <div class="grid grid-cols-2 gap-4">
                    <div>
                        <label class="text-[11px] text-zinc-400 font-semibold mb-1 block">Nombre del sitio</label>
                        <input type="text" id="website-name" placeholder="Mi sitio">
                    </div>
                    <div>
                        <label class="text-[11px] text-zinc-400 font-semibold mb-1 block">Ruta (slug)</label>
                        <input type="text" id="website-slug" placeholder="mi-sitio">
                        <p class="text-[9px] text-zinc-500 mt-1">URL: https://$DOMAIN/<span id="slug-preview">mi-sitio</span></p>
                    </div>
                </div>
                <div>
                    <label class="text-[11px] text-zinc-400 font-semibold mb-1 block">Código HTML</label>
                    <textarea id="website-content" class="code-editor w-full p-3 bg-zinc-950 border border-white/10 rounded-xl text-white" rows="12" spellcheck="false">&lt;!DOCTYPE html&gt;
&lt;html&gt;
&lt;head&gt;
    &lt;title&gt;Mi sitio&lt;/title&gt;
    &lt;style&gt;
        body { font-family: Arial; text-align: center; padding: 50px; background: #0c0c12; color: white; }
        h1 { color: #34d399; }
    &lt;/style&gt;
&lt;/head&gt;
&lt;body&gt;
    &lt;h1&gt;¡Hola desde GZMBOT Workers!&lt;/h1&gt;
    &lt;p&gt;Este sitio está alojado en tu propio servidor.&lt;/p&gt;
&lt;/body&gt;
&lt;/html&gt;</textarea>
                </div>
                <input type="hidden" id="website-edit-id">
                <div class="flex gap-3 justify-end">
                    <button onclick="closeWebsiteModal()" class="px-4 py-2 bg-zinc-800 rounded-xl text-xs text-white">Cancelar</button>
                    <button onclick="saveWebsite()" class="px-4 py-2 btn-green rounded-xl text-xs"><i data-lucide="save" class="w-4 h-4 inline mr-1"></i> Guardar</button>
                </div>
            </div>
        </div>
    </div>
    <header class="header-island">
        <div class="brand">
            <i data-lucide="bot" class="logo-icon w-6 h-6"></i>
            <span class="logo-text">GZMBOT</span>
        </div>
        <div class="right-group">
            <div class="clock" id="clockDisplay">
                <span id="clock-time">--:--:--</span>
                <span class="date" id="clock-date">Cargando...</span>
            </div>
            <button class="menu-btn" id="menuToggle" onclick="toggleMenu()">
                <i data-lucide="menu" class="w-5 h-5"></i>
            </button>
        </div>
    </header>
    <nav class="dropdown-menu" id="dropdownMenu">
        <button class="menu-item active" data-page="dash"><i data-lucide="layout-dashboard"></i> Dashboard</button>
        <button class="menu-item" data-page="conn"><i data-lucide="qr-code"></i> Conexión</button>
        <button class="menu-item" data-page="train"><i data-lucide="message-circle"></i> Respuestas</button>
        <button class="menu-item" data-page="rem"><i data-lucide="calendar-clock"></i> Recordatorios</button>
        <button class="menu-item" data-page="excl"><i data-lucide="user-x"></i> Excluidos</button>
        <button class="menu-item" data-page="workers"><i data-lucide="code"></i> Workers</button>
        <button class="menu-item" data-page="config"><i data-lucide="settings"></i> Ajustes</button>
        <div class="menu-divider"></div>
        <button class="menu-item" onclick="logout()" style="color:#f87171;"><i data-lucide="log-out"></i> Cerrar sesión</button>
        <div class="menu-footer">GZMBOT • RD</div>
    </nav>
    <main id="main-content" class="flex-1 flex flex-col min-h-screen overflow-x-hidden">
        <div class="p-6 sm:p-8 flex-1 max-w-7xl w-full mx-auto space-y-8">
            <!-- Dashboard -->
            <div id="p-dash" class="page active">
                <div class="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-4 mb-8">
                    <span id="status-badge" class="status-badge">
                        <span class="dot"></span> Desconectado
                    </span>
                </div>
                <div class="grid grid-cols-1 sm:grid-cols-3 gap-4 mb-8">
                    <div class="glass-card p-5 rounded-2xl flex items-center gap-4"><div class="p-3.5 bg-green-500/10 text-green-400 rounded-xl"><i data-lucide="message-square" class="w-6 h-6 text-white"></i></div><div><p class="text-xs text-zinc-400">Respuestas Automáticas</p><h3 id="s-replied" class="text-2xl font-black mt-0.5 text-white">0</h3></div></div>
                    <div class="glass-card p-5 rounded-2xl flex items-center gap-4"><div class="p-3.5 bg-green-500/10 text-green-400 rounded-xl"><i data-lucide="activity" class="w-6 h-6 text-white"></i></div><div><p class="text-xs text-zinc-400">Mensajes Procesados</p><h3 id="s-total" class="text-2xl font-black mt-0.5 text-white">0</h3></div></div>
                    <div class="glass-card p-5 rounded-2xl flex items-center gap-4"><div class="p-3.5 bg-green-500/10 text-green-400 rounded-xl"><i data-lucide="bell" class="w-6 h-6 text-white"></i></div><div><p class="text-xs text-zinc-400">Recordatorios</p><h3 id="today-reminders-count" class="text-2xl font-black mt-0.5 text-white">0</h3></div></div>
                </div>
                <div class="grid grid-cols-1 lg:grid-cols-3 gap-6">
                    <div class="glass-card p-6 rounded-3xl lg:col-span-2">
                        <div class="flex justify-between items-center mb-6"><div><h3 class="text-base font-bold text-white">Flujo de Mensajes Semanal</h3><p class="text-xs text-zinc-500">Estadística de mensajes procesados</p></div><span id="weekly-aggregate-total" class="text-xs font-mono text-green-400 font-bold bg-green-500/5 px-2 py-1 rounded-md">Total: 0 msgs</span></div>
                        <div class="relative h-64 w-full flex items-end justify-between pt-8 px-2 border-b border-white/5">
                            <div class="absolute inset-x-0 top-0 bottom-0 flex flex-col justify-between pointer-events-none text-[9px] text-zinc-700"><div class="border-t border-white/[0.03] w-full pt-1" id="y-max-val">1,200 msgs</div><div class="border-t border-white/[0.03] w-full pt-1" id="y-mid-val">600 msgs</div><div class="w-full">0 msgs</div></div>
                            <div id="bar-lun" class="w-[11%] bg-gradient-to-t from-green-600/20 to-green-400/40 hover:from-green-500/30 hover:to-green-300/50 transition-all rounded-t-xl flex flex-col justify-end items-center group relative z-10" style="height: 10%;"><div class="absolute -top-10 bg-zinc-900 border border-white/10 text-[10px] font-bold px-2 py-1 rounded-lg text-white opacity-0 group-hover:opacity-100 transition-opacity shadow-xl" id="tip-lun">0 msgs</div><span class="text-[10px] text-zinc-400 font-bold mb-1" id="val-lun">0</span><span class="text-[10px] text-zinc-500 font-medium absolute bottom-[-24px]">Lun</span></div>
                            <div id="bar-mar" class="w-[11%] bg-gradient-to-t from-green-600/20 to-green-400/40 hover:from-green-500/30 hover:to-green-300/50 transition-all rounded-t-xl flex flex-col justify-end items-center group relative z-10" style="height: 10%;"><div class="absolute -top-10 bg-zinc-900 border border-white/10 text-[10px] font-bold px-2 py-1 rounded-lg text-white opacity-0 group-hover:opacity-100 transition-opacity shadow-xl" id="tip-mar">0 msgs</div><span class="text-[10px] text-zinc-400 font-bold mb-1" id="val-mar">0</span><span class="text-[10px] text-zinc-500 font-medium absolute bottom-[-24px]">Mar</span></div>
                            <div id="bar-mie" class="w-[11%] bg-gradient-to-t from-green-600/20 to-green-400/40 hover:from-green-500/30 hover:to-green-300/50 transition-all rounded-t-xl flex flex-col justify-end items-center group relative z-10" style="height: 10%;"><div class="absolute -top-10 bg-zinc-900 border border-white/10 text-[10px] font-bold px-2 py-1 rounded-lg text-white opacity-0 group-hover:opacity-100 transition-opacity shadow-xl" id="tip-mie">0 msgs</div><span class="text-[10px] text-zinc-400 font-bold mb-1" id="val-mie">0</span><span class="text-[10px] text-zinc-500 font-medium absolute bottom-[-24px]">Mié</span></div>
                            <div id="bar-jue" class="w-[11%] bg-gradient-to-t from-green-600/20 to-green-400/40 hover:from-green-500/30 hover:to-green-300/50 transition-all rounded-t-xl flex flex-col justify-end items-center group relative z-10" style="height: 10%;"><div class="absolute -top-10 bg-zinc-900 border border-white/10 text-[10px] font-bold px-2 py-1 rounded-lg text-white opacity-0 group-hover:opacity-100 transition-opacity shadow-xl" id="tip-jue">0 msgs</div><span class="text-[10px] text-zinc-400 font-bold mb-1" id="val-jue">0</span><span class="text-[10px] text-zinc-500 font-medium absolute bottom-[-24px]">Jue</span></div>
                            <div id="bar-vie" class="w-[11%] bg-gradient-to-t from-green-600/20 to-green-400/40 hover:from-green-500/30 hover:to-green-300/50 transition-all rounded-t-xl flex flex-col justify-end items-center group relative z-10" style="height: 10%;"><div class="absolute -top-10 bg-zinc-900 border border-white/10 text-[10px] font-bold px-2 py-1 rounded-lg text-white opacity-0 group-hover:opacity-100 transition-opacity shadow-xl" id="tip-vie">0 msgs</div><span class="text-[10px] text-zinc-400 font-bold mb-1" id="val-vie">0</span><span class="text-[10px] text-zinc-500 font-medium absolute bottom-[-24px]">Vie</span></div>
                            <div id="bar-sab" class="w-[11%] bg-gradient-to-t from-green-600/20 to-green-400/40 hover:from-green-500/30 hover:to-green-300/50 transition-all rounded-t-xl flex flex-col justify-end items-center group relative z-10" style="height: 10%;"><div class="absolute -top-10 bg-zinc-900 border border-white/10 text-[10px] font-bold px-2 py-1 rounded-lg text-white opacity-0 group-hover:opacity-100 transition-opacity shadow-xl" id="tip-sab">0 msgs</div><span class="text-[10px] text-zinc-400 font-bold mb-1" id="val-sab">0</span><span class="text-[10px] text-zinc-500 font-medium absolute bottom-[-24px]">Sáb</span></div>
                            <div id="bar-dom" class="w-[11%] bg-gradient-to-t from-green-600/20 to-green-400/40 hover:from-green-500/30 hover:to-green-300/50 transition-all rounded-t-xl flex flex-col justify-end items-center group relative z-10" style="height: 10%;"><div class="absolute -top-10 bg-zinc-900 border border-white/10 text-[10px] font-bold px-2 py-1 rounded-lg text-white opacity-0 group-hover:opacity-100 transition-opacity shadow-xl" id="tip-dom">0 msgs</div><span class="text-[10px] text-zinc-400 font-bold mb-1" id="val-dom">0</span><span class="text-[10px] text-zinc-500 font-medium absolute bottom-[-24px]">Dom</span></div>
                        </div>
                        <div class="h-6"></div>
                    </div>
                    <div class="glass-card p-6 rounded-3xl flex flex-col justify-between">
                        <div><div class="flex items-center gap-2 mb-4"><i data-lucide="calendar" class="w-5 h-5 text-green-400"></i><h3 class="text-base font-bold text-white">Próximos Envíos</h3></div><div class="space-y-3" id="dashboard-upcoming-reminders"><div class="text-center py-8 text-xs text-zinc-500">No hay recordatorios pendientes.</div></div></div>
                        <button onclick="navigateTo('rem')" class="w-full mt-4 py-3 btn-green rounded-xl text-xs flex items-center justify-center gap-1.5"><i data-lucide="plus" class="w-4.5 h-4.5"></i> Programar Mensaje</button>
                    </div>
                </div>
            </div>
            <!-- Conexión -->
            <div id="p-conn" class="page">
                <div class="mb-6 text-center sm:text-left"><h2 class="text-3xl font-black text-white">Vincular dispositivo</h2><p class="text-xs text-zinc-400 mt-1">Elige el método para conectar tu bot a WhatsApp.</p></div>
                <div class="glass-card rounded-[2.5rem] p-6" id="connection-container">
                    <div class="connected-message" id="connected-message">
                        <div class="w-16 h-16 bg-green-500/15 rounded-full flex items-center justify-center mb-4"><i data-lucide="check-circle-2" class="w-8 h-8 text-green-400"></i></div>
                        <h3 class="text-xl font-bold text-white font-outfit">Dispositivo vinculado</h3>
                        <p class="text-zinc-400 text-sm mt-1">WhatsApp está conectado correctamente.</p>
                        <button onclick="logoutWA()" class="mt-6 px-6 py-3 btn-red-solid rounded-xl font-bold text-xs flex items-center gap-2"><i data-lucide="unplug" class="w-4 h-4"></i> Desvincular</button>
                    </div>
                    <div id="connection-content">
                        <div id="conn-qr" class="flex flex-col lg:flex-row items-center justify-center gap-8">
                            <div class="w-full lg:w-1/2 flex flex-col items-center">
                                <div class="qr-wrapper">
                                    <div id="qr-container" class="w-72 h-72 relative bg-zinc-900 flex items-center justify-center rounded-2xl overflow-hidden">
                                        <div id="qr-img" class="w-full h-full flex flex-col items-center justify-center">
                                            <span class="text-zinc-500 font-bold text-sm text-center">Cargando código QR...</span>
                                        </div>
                                    </div>
                                </div>
                                <div id="connected-container" class="hidden text-center mt-4">
                                    <div class="flex items-center gap-2 text-green-400"><i data-lucide="check-circle-2" class="w-5 h-5"></i><span class="text-sm font-bold">WhatsApp Vinculado</span></div>
                                </div>
                            </div>
                            <div class="w-full lg:w-1/2 space-y-6">
                                <h3 class="text-lg font-bold text-white font-outfit">Pasos para vincular</h3>
                                <ul class="space-y-4 text-xs text-zinc-400">
                                    <li class="flex gap-3 items-center"><span class="w-6 h-6 rounded-lg bg-green-600/10 text-green-400 flex items-center justify-center font-bold">1</span><span>Abre WhatsApp en tu celular.</span></li>
                                    <li class="flex gap-3 items-center"><span class="w-6 h-6 rounded-lg bg-green-600/10 text-green-400 flex items-center justify-center font-bold">2</span><span>Menú → Dispositivos vinculados.</span></li>
                                    <li class="flex gap-3 items-center"><span class="w-6 h-6 rounded-lg bg-green-600/10 text-green-400 flex items-center justify-center font-bold">3</span><span>Escanea el QR para autorizar.</span></li>
                                </ul>
                                <button onclick="toggleConnectionMethod()" class="w-full py-3 connection-toggle-btn font-bold rounded-xl text-sm flex items-center justify-center gap-2 transition-all">
                                    <i data-lucide="key-round" class="w-4 h-4"></i> Vincular con código de 8 dígitos
                                </button>
                            </div>
                        </div>
                        <div id="conn-code" class="hidden flex flex-col items-center justify-center gap-6 py-6">
                            <div class="w-full max-w-md space-y-4">
                                <p class="text-sm text-zinc-400 text-center">Ingresa tu número con código de país para obtener un código de 8 dígitos.</p>
                                <div class="flex gap-3">
                                    <input type="text" id="pairing-phone" placeholder="Ej: 521234567890" class="flex-1">
                                    <button onclick="requestPairingCode()" class="px-6 py-3 btn-green rounded-xl text-sm flex items-center gap-2"><i data-lucide="key" class="w-4 h-4"></i> Obtener</button>
                                </div>
                                <div id="pairing-result" class="hidden text-center">
                                    <div class="bg-green-500/10 border border-green-500/20 p-4 rounded-xl">
                                        <p class="text-xs text-zinc-400">Código de emparejamiento (introdúcelo en tu WhatsApp móvil):</p>
                                        <p id="pairing-code-display" class="text-3xl font-mono font-bold text-green-400 mt-2 tracking-widest select-all">------</p>
                                    </div>
                                    <button onclick="copyPairingCode()" class="mt-3 px-4 py-2 copy-btn font-bold rounded-xl text-xs flex items-center gap-2 mx-auto transition-all">
                                        <i data-lucide="copy" class="w-4 h-4"></i> Copiar código
                                    </button>
                                    <p class="text-[10px] text-zinc-500 mt-3">El código expira en 2 minutos.</p>
                                </div>
                                <button onclick="toggleConnectionMethod()" class="w-full py-2 text-sm text-zinc-400 hover:text-white transition-colors flex items-center justify-center gap-2">
                                    <i data-lucide="arrow-left" class="w-4 h-4"></i> Volver al código QR
                                </button>
                            </div>
                        </div>
                    </div>
                </div>
            </div>
            <!-- Respuestas -->
            <div id="p-train" class="page">
                <div class="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-4 mb-6"><div><h2 class="text-3xl font-black text-white">Respuestas del Bot</h2><p class="text-xs text-zinc-400 mt-1 font-medium">Asocia preguntas frecuentes con respuestas automáticas directas.</p></div><div class="flex gap-2"><button onclick="downloadTemplate()" class="px-4 py-2.5 btn-green rounded-xl text-xs flex items-center gap-1.5"><i data-lucide="file-text" class="w-4 h-4"></i> Plantilla</button><button onclick="document.getElementById('import-file').click()" class="px-4 py-2.5 btn-green rounded-xl text-xs flex items-center gap-1.5"><i data-lucide="file-plus" class="w-4.5 h-4.5"></i> Importar</button><input type="file" id="import-file" accept=".txt,.csv" class="hidden" onchange="importTraining(this)"></div></div>
                <div class="grid lg:grid-cols-3 gap-6">
                    <div class="glass-card p-6 rounded-3xl h-fit">
                        <h3 class="font-bold mb-4 text-sm text-zinc-300 uppercase tracking-wider">Formular Regla</h3>
                        <form id="train-form" enctype="multipart/form-data" onsubmit="saveTrain(event)" class="space-y-4">
                            <input type="hidden" id="t-id">
                            <div><label class="text-[11px] text-zinc-400 font-semibold mb-1 block">Palabra(s) clave de activación</label><input type="text" id="t-key" placeholder="Ej: horario, informacion" required></div>
                            <div><label class="text-[11px] text-zinc-400 font-semibold mb-1 block">Texto de respuesta</label><textarea id="t-res" placeholder="Escribe el mensaje de respuesta..." rows="4" required></textarea></div>
                            <div><label class="text-[11px] text-zinc-400 font-semibold mb-2 block">Tipo de Mensaje</label>
                                <div class="flex gap-2">
                                    <button type="button" onclick="setMediaType('text')" id="mt-text" class="media-type-btn active flex-1">Texto</button>
                                    <button type="button" onclick="setMediaType('image')" id="mt-image" class="media-type-btn flex-1">Imagen</button>
                                    <button type="button" onclick="setMediaType('video')" id="mt-video" class="media-type-btn flex-1">Video</button>
                                </div>
                            </div>
                            <div id="media-upload" class="hidden">
                                <label class="text-[11px] text-zinc-400 font-semibold mb-1 block">Adjuntar Archivo(s)</label>
                                <input type="file" id="t-media" name="media" accept="image/*,video/*" multiple class="py-2.5 text-xs">
                                <div id="media-preview" class="flex flex-wrap gap-2 mt-2"></div>
                            </div>
                            <button type="submit" class="w-full py-4 btn-green rounded-2xl text-xs flex items-center justify-center gap-2"><i data-lucide="save" class="w-4 h-4"></i> Guardar Regla</button>
                        </form>
                    </div>
                    <div class="lg:col-span-2 space-y-3" id="l-train"></div>
                </div>
            </div>
            <!-- Recordatorios -->
            <div id="p-rem" class="page"><h2 class="text-3xl font-black text-white mb-6">Programar Mensajes</h2><div class="glass-card p-6 rounded-3xl mb-6"><input type="hidden" id="r-id"><div class="grid grid-cols-1 md:grid-cols-2 gap-4"><div><label class="text-[11px] text-zinc-400 font-semibold mb-1 block">Identificador</label><input type="text" id="r-name" placeholder="Ej: Juan Pérez"></div><div><label class="text-[11px] text-zinc-400 font-semibold mb-1 block">Número de WhatsApp</label><div class="flex gap-2"><input type="text" id="r-phone" placeholder="Ej: 18091234567" class="flex-1"><button type="button" onclick="openContactModal('r-phone', 'r-name')" class="w-12 h-12 rounded-full contact-select-btn flex items-center justify-center shadow-lg transition-all"><i data-lucide="users" class="w-5 h-5"></i></button></div></div><div class="md:col-span-2"><label class="text-[11px] text-zinc-400 font-semibold mb-1 block">Mensaje</label><textarea id="r-msg" placeholder="Escribe el mensaje..." rows="2"></textarea></div><div><label class="text-[11px] text-zinc-400 font-semibold mb-1 block">Frecuencia</label><select id="r-freq"><option>Una vez</option><option>Diario</option><option>Semanal</option><option>Mensual</option><option>Anual</option></select></div><div><label class="text-[11px] text-zinc-400 font-semibold mb-1 block">Fecha y Hora</label><input type="datetime-local" id="r-date" class="w-full"></div></div><button onclick="saveRem()" class="mt-5 w-full py-4 btn-green rounded-2xl text-xs flex items-center justify-center gap-2"><i data-lucide="clock" class="w-4 h-4"></i> Programar Envío</button></div><div id="l-rem" class="grid grid-cols-1 md:grid-cols-2 gap-4"></div></div>
            <!-- Excluidos -->
            <div id="p-excl" class="page"><h2 class="text-3xl font-black text-white mb-6">Contactos Excluidos</h2><div class="glass-card p-6 rounded-3xl"><div class="grid grid-cols-1 md:grid-cols-3 gap-4 mb-6 items-end"><div class="md:col-span-1"><label class="text-[11px] text-zinc-400 font-semibold mb-1 block">Nombre</label><input type="text" id="e-name" placeholder="Ej: Socio Distribuidor"></div><div class="md:col-span-1"><label class="text-[11px] text-zinc-400 font-semibold mb-1 block">Número</label><div class="flex gap-2"><input type="text" id="e-phone" placeholder="Ej: 18091234567" class="flex-1"><button type="button" onclick="openContactModal('e-phone', 'e-name')" class="w-12 h-12 rounded-full contact-select-btn flex items-center justify-center shadow-lg transition-all"><i data-lucide="users" class="w-5 h-5"></i></button></div></div><button onclick="saveExcl()" class="h-12 btn-green rounded-2xl text-xs flex items-center justify-center gap-1.5"><i data-lucide="user-plus" class="w-4 h-4"></i> Excluir</button></div><div id="l-excl" class="space-y-2"></div></div></div>
            <!-- Workers -->
            <div id="p-workers" class="page">
                <div class="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-4 mb-6">
                    <div><h2 class="text-3xl font-black text-white">Workers</h2><p class="text-xs text-zinc-400 mt-1">Crea y aloja sitios web estáticos en tu propio dominio.</p></div>
                    <button onclick="openWebsiteEditor()" class="px-4 py-2.5 btn-green rounded-xl text-xs flex items-center gap-1.5"><i data-lucide="file-plus" class="w-4.5 h-4.5"></i> Nuevo sitio</button>
                </div>
                <div id="websites-list" class="grid grid-cols-1 md:grid-cols-2 gap-4">
                    <div class="text-center py-8 text-zinc-500 col-span-2">No hay sitios creados. Haz clic en "Nuevo sitio" para comenzar.</div>
                </div>
            </div>
            <!-- Configuración -->
            <div id="p-config" class="page"><h2 class="text-3xl font-black text-white mb-6">Ajustes del Sistema</h2><div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
                <div class="glass-card p-6 rounded-3xl lg:col-span-2">
                    <div class="flex items-center justify-between mb-4"><h3 class="font-bold text-base text-zinc-300">Rendimiento del Servidor</h3><span class="text-[10px] bg-green-600/10 text-green-400 px-2 py-1 rounded-md font-bold tracking-widest">LIVE</span></div>
                    <div class="grid grid-cols-1 md:grid-cols-2 gap-8">
                        <div class="bg-zinc-950/40 border border-white/[0.02] p-4 rounded-2xl text-center">
                            <p class="text-xs text-zinc-500 font-bold uppercase tracking-wider mb-2">Carga de CPU</p>
                            <div class="flex items-center gap-3 justify-center">
                                <span id="cpu-label" class="text-2xl font-mono text-green-400">0%</span>
                                <div class="w-40 performance-bar"><div id="cpu-fill" class="fill bg-green-500" style="width:0%"></div></div>
                            </div>
                        </div>
                        <div class="bg-zinc-950/40 border border-white/[0.02] p-4 rounded-2xl text-center">
                            <p class="text-xs text-zinc-500 font-bold uppercase tracking-wider mb-2">Memoria RAM</p>
                            <div class="flex items-center gap-3 justify-center">
                                <span id="ram-label" class="text-2xl font-mono text-green-400">0%</span>
                                <div class="w-40 performance-bar"><div id="ram-fill" class="fill bg-green-500" style="width:0%"></div></div>
                            </div>
                        </div>
                    </div>
                </div>
                <div class="glass-card p-6 rounded-3xl"><h3 class="font-bold text-base mb-4 text-zinc-300">Credenciales del Panel</h3><div class="space-y-4"><input type="text" id="conf-user" placeholder="Usuario maestro"><input type="password" id="conf-pass" placeholder="Contraseña de acceso"><button onclick="saveCredentials()" class="w-full py-4 btn-green rounded-2xl text-xs flex items-center justify-center gap-2"><i data-lucide="key" class="w-4 h-4"></i> Guardar Credenciales</button></div></div>
                <div class="glass-card p-6 rounded-3xl">
                    <h3 class="font-bold text-base mb-4 text-zinc-300 font-outfit">Copias de Seguridad</h3>
                    <div class="space-y-5">
                        <div>
                            <label class="text-[11px] text-zinc-400 font-semibold block mb-1">Número de respaldo (WhatsApp)</label>
                            <div class="flex gap-2">
                                <input type="text" id="conf-backup-phone" placeholder="Ej: 18091234567" class="flex-1">
                                <button type="button" onclick="openContactModal('conf-backup-phone', null)" class="w-12 h-12 rounded-full contact-select-btn flex items-center justify-center shadow-lg transition-all"><i data-lucide="users" class="w-5 h-5"></i></button>
                                <button onclick="saveBackupPhone()" class="px-4 py-2 btn-green rounded-xl text-xs flex items-center gap-1.5"><i data-lucide="save" class="w-4 h-4"></i> Guardar</button>
                            </div>
                        </div>
                        <div>
                            <label class="text-[11px] text-zinc-400 font-semibold block mb-1">Hora de envío automático (24h)</label>
                            <div class="flex items-center gap-2">
                                <input type="time" id="conf-backup-hour" value="12:00" class="flex-1" step="60">
                                <button onclick="saveBackupHour()" class="px-4 py-2.5 btn-green rounded-xl text-xs flex items-center gap-1.5"><i data-lucide="clock" class="w-4 h-4"></i> Guardar hora</button>
                            </div>
                            <p class="text-[10px] text-zinc-500 mt-1">Se enviará automáticamente a la hora indicada, solo si el bot está conectado.</p>
                        </div>
                        <div class="grid grid-cols-3 gap-2 mt-2">
                            <button onclick="downloadBackup()" class="py-3 btn-green rounded-xl text-xs flex items-center justify-center gap-1.5"><i data-lucide="download" class="w-4.5 h-4.5"></i> Descargar</button>
                            <button onclick="sendBackupManually()" class="py-3 btn-green rounded-xl text-xs flex items-center justify-center gap-1.5"><i data-lucide="send" class="w-4.5 h-4.5"></i> Enviar WA</button>
                            <button onclick="document.getElementById('restore-file').click()" class="py-3 btn-green rounded-xl text-xs flex items-center justify-center gap-1.5"><i data-lucide="upload" class="w-4.5 h-4.5"></i> Restaurar</button>
                            <input type="file" id="restore-file" accept=".json" class="hidden" onchange="restoreBackup(this)">
                        </div>
                    </div>
                </div>
                <div class="glass-card p-6 rounded-3xl lg:col-span-2"><h3 class="font-bold text-base mb-5 text-zinc-300">Tiempos y Parámetros</h3><div class="grid md:grid-cols-2 gap-6 mb-6"><div class="space-y-2"><div class="flex justify-between text-xs font-bold text-zinc-400"><span>Retardo antes de responder (segundos)</span><span id="delay-value" class="text-green-400 font-mono">0.0 s</span></div><input type="range" id="response-delay" min="0" max="10" step="0.5" value="0" class="w-full"></div><div class="space-y-2"><div class="flex justify-between text-xs font-bold text-zinc-400"><span>Intervalo cola (milisegundos)</span><span id="interval-value" class="text-green-400 font-mono">3000 ms</span></div><input type="range" id="queue-interval" min="500" max="10000" step="100" value="3000" class="w-full"></div></div><button onclick="saveConfiguracionEnvio()" class="w-full py-4 btn-green rounded-2xl text-xs flex items-center justify-center gap-2"><i data-lucide="save" class="w-4.5 h-4.5"></i> Guardar Configuración</button></div>
            </div></div>
        </div>
    </main>
    <script>
        const socket = io();
        let db = { training:[], reminders:[], excluded:[], stats:{ replied:0, total:0, lastBackupDate:null }, websites:[], backupPhone:'', backupHour:'12:00', responseDelay:0, queueInterval:3000 };
        let currentMediaType = 'text';
        let selectedFiles = [];
        let existingMediaFiles = [];
        let contacts = [];
        let activeInputId = null;
        let rendering = false;
        let pairingCode = '';

        // ===== OPTIMIZACIÓN: Throttle de renderizado =====
        let renderTimeout = null;
        function scheduleRender() {
            if (renderTimeout) return;
            renderTimeout = requestAnimationFrame(() => {
                render();
                renderTimeout = null;
            });
        }

        function showToast(message, type='info', duration=4000) {
            const container = document.getElementById('toastContainer');
            const toast = document.createElement('div');
            const iconMap = { info:'info', success:'check-circle', error:'alert-circle', warning:'alert-triangle' };
            const titleMap = { info:'Información', success:'Éxito', error:'Error', warning:'Advertencia' };
            toast.className = `toast toast-${type}`;
            toast.innerHTML = `
                <div class="toast-icon"><i data-lucide="${iconMap[type]}" class="w-5 h-5"></i></div>
                <div class="toast-body">
                    <div class="toast-title">${titleMap[type]}</div>
                    <div class="toast-message">${message}</div>
                </div>
                <button class="toast-close" onclick="this.closest('.toast').remove()"><i data-lucide="x" class="w-4 h-4"></i></button>
            `;
            container.appendChild(toast);
            lucide.createIcons();
            requestAnimationFrame(() => toast.classList.add('show'));
            setTimeout(() => {
                toast.classList.remove('show');
                setTimeout(() => toast.remove(), 300);
            }, duration);
        }

        function showConfirm(message, callback) {
            const modal = document.getElementById('contactModal');
            const content = modal.querySelector('.modal-content');
            const originalHtml = content.innerHTML;
            content.innerHTML = `
                <div class="flex justify-between items-center mb-4">
                    <h3 class="text-lg font-bold text-white">Confirmar</h3>
                    <button onclick="closeConfirm()" class="text-zinc-400 hover:text-white"><i data-lucide="x" class="w-5 h-5"></i></button>
                </div>
                <p class="text-zinc-300 text-sm mb-6">${message}</p>
                <div class="flex gap-3 justify-end">
                    <button onclick="closeConfirm(); window.confirmCallback(false);" class="px-4 py-2 bg-zinc-800 rounded-xl text-xs text-white">Cancelar</button>
                    <button onclick="closeConfirm(); window.confirmCallback(true);" class="px-4 py-2 btn-red-solid rounded-xl text-xs">Aceptar</button>
                </div>
            `;
            modal.classList.add('active');
            window.confirmCallback = callback;
            window.confirmOriginalHtml = originalHtml;
        }

        function closeConfirm() {
            const modal = document.getElementById('contactModal');
            modal.classList.remove('active');
            setTimeout(() => {
                const content = modal.querySelector('.modal-content');
                content.innerHTML = window.confirmOriginalHtml || `
                    <div class="flex justify-between items-center mb-4">
                        <h3 class="text-lg font-bold text-white">Seleccionar contacto</h3>
                        <button onclick="closeContactModal()" class="text-zinc-400 hover:text-white"><i data-lucide="x" class="w-5 h-5"></i></button>
                    </div>
                    <input type="text" id="contactSearch" placeholder="Buscar por nombre o número..." class="mb-4 text-sm">
                    <div id="contactList" class="space-y-2 max-h-96 overflow-y-auto"></div>
                    <div class="mt-4 text-center text-xs text-zinc-500">O escribe el número manualmente en el campo</div>
                `;
                lucide.createIcons();
                setupContactSearch();
            }, 200);
        }

        const dropdownMenu = document.getElementById('dropdownMenu');
        const menuOverlay = document.getElementById('menuOverlay');
        function toggleMenu() { dropdownMenu.classList.contains('open') ? closeMenu() : openMenu(); }
        function openMenu() { dropdownMenu.classList.add('open'); menuOverlay.classList.add('active'); }
        function closeMenu() { dropdownMenu.classList.remove('open'); menuOverlay.classList.remove('active'); }
        function navigateTo(pageId) {
            closeMenu();
            document.querySelectorAll('.page').forEach(p => p.classList.remove('active'));
            document.getElementById('p-'+pageId).classList.add('active');
            document.querySelectorAll('.dropdown-menu .menu-item').forEach(item => {
                item.classList.remove('active');
                if (item.dataset.page === pageId) item.classList.add('active');
            });
            lucide.createIcons();
        }
        document.querySelectorAll('.dropdown-menu .menu-item[data-page]').forEach(item => {
            item.addEventListener('click', function() { navigateTo(this.dataset.page); });
        });

        function toggleConnectionMethod() {
            const qr = document.getElementById('conn-qr');
            const code = document.getElementById('conn-code');
            if (qr.classList.contains('hidden')) { qr.classList.remove('hidden'); code.classList.add('hidden'); }
            else { qr.classList.add('hidden'); code.classList.remove('hidden'); }
        }
        function copyPairingCode() {
            const code = document.getElementById('pairing-code-display').textContent;
            if (code && code!=='------') {
                navigator.clipboard.writeText(code).then(() => showToast('Código copiado', 'success'))
                    .catch(() => { const ta=document.createElement('textarea'); ta.value=code; document.body.appendChild(ta); ta.select(); document.execCommand('copy'); ta.remove(); showToast('Código copiado', 'success'); });
            }
        }

        let lastCpu = -1, lastRam = -1;

        socket.on('sys_stats', data => {
            const cpu = Math.round(data.cpu);
            const ram = Math.round(data.ram);
            if (cpu !== lastCpu) {
                document.getElementById('cpu-label').textContent = cpu + '%';
                document.getElementById('cpu-fill').style.width = Math.min(cpu, 100) + '%';
                lastCpu = cpu;
            }
            if (ram !== lastRam) {
                document.getElementById('ram-label').textContent = ram + '%';
                document.getElementById('ram-fill').style.width = Math.min(ram, 100) + '%';
                lastRam = ram;
            }
        });
        socket.on('pairing_code', code => { pairingCode=code; document.getElementById('pairing-result').classList.remove('hidden'); document.getElementById('pairing-code-display').textContent=code; });
        socket.on('connection_status', data => {
            const qrContainer = document.getElementById('qr-container');
            const connDiv = document.getElementById('connected-container');
            const badge = document.getElementById('status-badge');
            const connectedMsg = document.getElementById('connected-message');
            const content = document.getElementById('connection-content');
            if (data.connected) {
                qrContainer.style.display='none'; connDiv.style.display='block';
                badge.className='status-badge connected'; badge.innerHTML='<span class="dot"></span> Conectado';
                connectedMsg.style.display='flex'; content.style.display='none';
            } else {
                qrContainer.style.display='flex'; connDiv.style.display='none';
                badge.className='status-badge'; badge.innerHTML='<span class="dot"></span> Desconectado';
                connectedMsg.style.display='none'; content.style.display='block';
            }
        });
        socket.on('qr_update', url => { document.getElementById('qr-img').innerHTML = `<img src="${url}" class="w-full h-full object-contain rounded-2xl">`; });
        socket.on('qr_clear', () => { document.getElementById('qr-img').innerHTML = '<span class="text-zinc-500 font-bold text-sm text-center">Esperando código QR...</span>'; });
        socket.on('data_update', data => {
            db = data;
            // Actualizar hora de backup en el campo time
            document.getElementById('conf-backup-hour').value = data.backupHour || '12:00';
            scheduleRender();
        });
        socket.on('contacts_update', newContacts => { contacts=newContacts; renderContactList(contacts); });

        // Reloj
        let clockTimeout = null;
        const clockDisplay = document.getElementById('clockDisplay');
        const clockTimeSpan = document.getElementById('clock-time');
        const clockDateSpan = document.getElementById('clock-date');

        function format12Hour(date) {
            let h=date.getHours(), m=date.getMinutes(), s=date.getSeconds();
            const ampm = h>=12 ? 'PM' : 'AM';
            h = h%12 || 12;
            return `${h}:${String(m).padStart(2,'0')}:${String(s).padStart(2,'0')} ${ampm}`;
        }

        function updateClock() {
            const now = new Date();
            if (!clockTimeout) {
                clockTimeSpan.textContent = format12Hour(now);
                clockDateSpan.textContent = now.toLocaleDateString('es-ES', { timeZone:'America/Santo_Domingo', weekday:'long', year:'numeric', month:'long', day:'numeric' });
            }
        }

        function showDateFor5Seconds() {
            if (clockTimeout) {
                clearTimeout(clockTimeout);
                clockTimeout = null;
            }
            const now = new Date();
            const dateStr = now.toLocaleDateString('es-ES', { timeZone:'America/Santo_Domingo', weekday:'long', year:'numeric', month:'long', day:'numeric' });
            clockTimeSpan.textContent = dateStr;
            clockDateSpan.textContent = '';
            clockTimeout = setTimeout(() => {
                const now2 = new Date();
                clockTimeSpan.textContent = format12Hour(now2);
                clockDateSpan.textContent = now2.toLocaleDateString('es-ES', { timeZone:'America/Santo_Domingo', weekday:'long', year:'numeric', month:'long', day:'numeric' });
                clockTimeout = null;
            }, 5000);
        }

        clockDisplay.addEventListener('click', showDateFor5Seconds);
        setInterval(() => {
            const now = new Date();
            if (!clockTimeout) {
                clockTimeSpan.textContent = format12Hour(now);
                clockDateSpan.textContent = now.toLocaleDateString('es-ES', { timeZone:'America/Santo_Domingo', weekday:'long', year:'numeric', month:'long', day:'numeric' });
            }
        }, 1000);

        async function requestPairingCode() {
            const phone = document.getElementById('pairing-phone').value.trim();
            if (!phone) { showToast('Ingresa un número válido', 'warning'); return; }
            document.getElementById('pairing-result').classList.add('hidden');
            showToast('Solicitando código...', 'info');
            try {
                const res = await fetch('/api/pairing', { method:'POST', headers:{'Content-Type':'application/json'}, body: JSON.stringify({ phone }) });
                const data = await res.json();
                if (data.ok) {
                    if (data.code) { document.getElementById('pairing-result').classList.remove('hidden'); document.getElementById('pairing-code-display').textContent = data.code; }
                    showToast('Código generado', 'success');
                } else showToast('Error: '+data.error, 'error');
            } catch (e) { showToast('Error al solicitar código', 'error'); }
        }

        function openContactModal(inputId, nameInputId) {
            activeInputId = inputId;
            window.nameInputIdLinked = nameInputId;
            const modal = document.getElementById('contactModal');
            modal.classList.add('active');
            socket.emit('force_refresh_contacts');
            document.getElementById('contactList').innerHTML = '<div class="text-center py-4 text-zinc-500">Cargando contactos...</div>';
            renderContactList(contacts);
            document.getElementById('contactSearch').value = '';
            document.getElementById('contactSearch').focus();
        }
        function renderContactList(filteredContacts) {
            const container = document.getElementById('contactList');
            if (!filteredContacts || !filteredContacts.length) {
                container.innerHTML = '<div class="text-center py-4 text-zinc-500">No hay contactos disponibles.</div>';
                return;
            }
            container.innerHTML = filteredContacts.map(c => `
                <div class="contact-item" onclick="selectContact('${c.number}', '${escapeHtml(c.name)}')">
                    <div class="font-medium text-white">${escapeHtml(c.name)}</div>
                    <div class="text-xs text-zinc-400">+${c.number}</div>
                </div>
            `).join('');
        }
        function selectContact(number, name) {
            if (activeInputId) {
                document.getElementById(activeInputId).value = number;
                if (window.nameInputIdLinked && document.getElementById(window.nameInputIdLinked)) document.getElementById(window.nameInputIdLinked).value = name;
            }
            closeContactModal();
        }
        function closeContactModal() { document.getElementById('contactModal').classList.remove('active'); activeInputId=null; window.nameInputIdLinked=null; }
        let searchTimeout=null;
        function setupContactSearch() {
            const input = document.getElementById('contactSearch');
            if (input) {
                input.addEventListener('input', (e) => {
                    clearTimeout(searchTimeout);
                    searchTimeout = setTimeout(() => {
                        const search = e.target.value.toLowerCase();
                        const filtered = contacts.filter(c => c.name.toLowerCase().includes(search) || c.number.includes(search));
                        renderContactList(filtered);
                    }, 300);
                });
            }
        }
        function escapeHtml(str) { if (!str) return ''; return str.replace(/[&<>]/g, m => ({'&':'&amp;','<':'&lt;','>':'&gt;'})[m]); }

        function setMediaType(type) {
            currentMediaType = type;
            document.querySelectorAll('.media-type-btn').forEach(b => b.classList.remove('active'));
            document.getElementById('mt-'+type).classList.add('active');
            document.getElementById('media-upload').classList.toggle('hidden', type === 'text');
            if (type !== 'text') document.getElementById('t-media').accept = type === 'image' ? 'image/*' : 'video/*';
        }

        function updateMediaPreview(files, existingPaths) {
            const preview = document.getElementById('media-preview');
            preview.innerHTML = '';
            selectedFiles = files ? Array.from(files) : [];

            if (existingPaths && existingPaths.length) {
                existingPaths.forEach((path, idx) => {
                    const div = document.createElement('div');
                    div.className = 'media-preview-item';
                    const isVideo = path.match(/\.(mp4|3gp|avi|mov)$/i);
                    const el = document.createElement(isVideo ? 'video' : 'img');
                    el.src = path;
                    if (isVideo) el.muted = true;
                    el.style.width = '80px'; el.style.height = '80px'; el.style.objectFit = 'cover'; el.style.borderRadius = '12px';
                    const btn = document.createElement('button');
                    btn.className = 'remove-media'; btn.innerHTML = '✕';
                    btn.onclick = (e) => {
                        e.preventDefault();
                        existingMediaFiles.splice(idx, 1);
                        updateMediaPreview(null, existingMediaFiles);
                    };
                    div.appendChild(el); div.appendChild(btn);
                    preview.appendChild(div);
                });
            }

            selectedFiles.forEach((f, idx) => {
                const reader = new FileReader();
                reader.onload = ev => {
                    const div = document.createElement('div');
                    div.className = 'media-preview-item';
                    const isVideo = f.type.startsWith('video/');
                    const el = document.createElement(isVideo ? 'video' : 'img');
                    el.src = ev.target.result;
                    if (isVideo) el.muted = true;
                    const btn = document.createElement('button');
                    btn.className = 'remove-media'; btn.innerHTML = '✕';
                    btn.onclick = (e) => {
                        e.preventDefault();
                        selectedFiles.splice(idx, 1);
                        updateMediaPreview(null, existingMediaFiles);
                    };
                    div.appendChild(el); div.appendChild(btn);
                    preview.appendChild(div);
                };
                reader.readAsDataURL(f);
            });

            if (!selectedFiles.length && !existingMediaFiles.length) {
                preview.innerHTML = '<span class="text-xs text-zinc-500">No hay archivos seleccionados</span>';
            }
        }

        document.getElementById('t-media').addEventListener('change', function(e) {
            const files = e.target.files;
            if (files.length) {
                selectedFiles = Array.from(files);
                updateMediaPreview(files, existingMediaFiles);
            } else {
                selectedFiles = [];
                updateMediaPreview(null, existingMediaFiles);
            }
        });

        function openWebsiteEditor(website=null) {
            const modal = document.getElementById('websiteModal');
            const title = document.getElementById('website-modal-title');
            const nameInput = document.getElementById('website-name');
            const slugInput = document.getElementById('website-slug');
            const contentInput = document.getElementById('website-content');
            const idInput = document.getElementById('website-edit-id');
            if (website) {
                title.textContent='Editar sitio web';
                nameInput.value=website.name;
                slugInput.value=website.slug;
                contentInput.value = website.content || '';
                idInput.value=website.id;
                document.getElementById('slug-preview').textContent=website.slug;
            } else {
                title.textContent='Crear sitio web';
                nameInput.value=''; slugInput.value='';
                contentInput.value=`<!DOCTYPE html>\n<html>\n<head><title>Mi sitio</title><style>body{font-family:Arial;text-align:center;padding:50px;background:#0c0c12;color:white;}h1{color:#34d399;}</style></head>\n<body><h1>¡Hola desde GZMBOT Workers!</h1><p>Este sitio está alojado en tu propio servidor.</p></body>\n</html>`;
                idInput.value='';
                document.getElementById('slug-preview').textContent='mi-sitio';
            }
            modal.classList.add('active');
        }
        function closeWebsiteModal() { document.getElementById('websiteModal').classList.remove('active'); }
        document.getElementById('website-slug').addEventListener('input', function() { document.getElementById('slug-preview').textContent = this.value || 'mi-sitio'; });

        async function saveWebsite() {
            let name = document.getElementById('website-name').value.trim();
            let slug = document.getElementById('website-slug').value.trim();
            const content = document.getElementById('website-content').value;
            const id = document.getElementById('website-edit-id').value;
            if (!name || !content) { showToast('Completa los campos nombre y contenido', 'warning'); return; }
            if (slug) slug = slug.trim().toLowerCase().replace(/\s+/g, '-').replace(/[^a-z0-9-]/g, '');
            if (!slug) { slug = name.trim().toLowerCase().replace(/\s+/g, '-').replace(/[^a-z0-9-]/g, ''); if (!slug) slug = 'site-'+Date.now(); }
            document.getElementById('website-slug').value = slug;
            document.getElementById('slug-preview').textContent = slug;
            try {
                let res = id ? await fetch('/api/websites/'+id, { method:'PUT', headers:{'Content-Type':'application/json'}, body: JSON.stringify({ name, slug, content }) })
                            : await fetch('/api/websites', { method:'POST', headers:{'Content-Type':'application/json'}, body: JSON.stringify({ name, slug, content }) });
                const data = await res.json();
                if (data.ok) { showToast(id ? 'Sitio actualizado' : 'Sitio creado', 'success'); closeWebsiteModal(); }
                else showToast('Error: '+ (data.error || 'desconocido'), 'error');
            } catch (e) { showToast('Error al guardar: '+e.message, 'error'); }
        }

        function renderWebsites() {
            const container = document.getElementById('websites-list');
            const websites = db.websites || [];
            if (!websites.length) { container.innerHTML = '<div class="text-center py-8 text-zinc-500 col-span-2">No hay sitios creados.</div>'; return; }
            container.innerHTML = websites.map(w => `
                <div class="glass-card p-4 rounded-xl website-card">
                    <div class="flex justify-between items-start">
                        <div>
                            <h4 class="text-white font-bold">${escapeHtml(w.name)}</h4>
                            <p class="text-xs text-zinc-400 font-mono">/${w.slug}</p>
                            <p class="text-[10px] text-zinc-500 mt-1">Creado: ${w.created_at || 'N/A'}</p>
                        </div>
                        <div class="flex gap-2">
                            <a href="/${w.slug}" target="_blank" class="p-2 btn-green rounded-lg text-xs flex items-center gap-1"><i data-lucide="external-link" class="w-4 h-4"></i></a>
                            <button onclick="editWebsite(${w.id})" class="p-2 btn-green rounded-lg text-xs"><i data-lucide="edit-3" class="w-4 h-4"></i></button>
                            <button onclick="deleteWebsite(${w.id})" class="p-2 btn-red-solid rounded-lg text-xs"><i data-lucide="trash-2" class="w-4 h-4"></i></button>
                        </div>
                    </div>
                </div>
            `).join('');
            lucide.createIcons();
        }

        function editWebsite(id) {
            const website = db.websites.find(w => w.id === id);
            if (website) openWebsiteEditor(website);
        }

        async function deleteWebsite(id) {
            const website = db.websites.find(w => w.id === id);
            if (!website) return;
            showConfirm(`¿Eliminar el sitio "${website.name}"?`, async (confirmed) => {
                if (!confirmed) return;
                try {
                    const res = await fetch('/api/websites/'+id, { method:'DELETE' });
                    const data = await res.json();
                    if (data.ok) { showToast('Sitio eliminado', 'success'); }
                    else showToast('Error al eliminar', 'error');
                } catch (e) { showToast('Error', 'error'); }
            });
        }

        async function saveTrain(e) {
            e.preventDefault();
            const fd = new FormData();
            fd.append('id', document.getElementById('t-id').value);
            fd.append('key', document.getElementById('t-key').value);
            fd.append('response', document.getElementById('t-res').value);
            fd.append('existingMedia', JSON.stringify(existingMediaFiles));
            if (currentMediaType !== 'text' && selectedFiles.length) {
                selectedFiles.forEach(f => fd.append('media', f));
            }
            try {
                const res = await fetch('/api/train', { method:'POST', body: fd });
                const data = await res.json();
                if (data.ok) {
                    showToast('Regla guardada correctamente', 'success');
                    resetTrainForm();
                } else showToast('Error al guardar: ' + (data.error || 'desconocido'), 'error');
            } catch (err) { showToast('Error de red: '+err.message, 'error'); }
        }

        function resetTrainForm() {
            document.getElementById('t-id').value = '';
            document.getElementById('t-key').value = '';
            document.getElementById('t-res').value = '';
            selectedFiles = [];
            existingMediaFiles = [];
            document.getElementById('t-media').value = '';
            setMediaType('text');
            updateMediaPreview(null, null);
        }

        function editT(id) {
            const t = db.training.find(t => t.id == id);
            if (!t) return;
            document.getElementById('t-id').value = t.id;
            document.getElementById('t-key').value = t.key;
            document.getElementById('t-res').value = t.response;
            const mediaPaths = t.mediaPaths ? JSON.parse(t.mediaPaths) : [];
            if (mediaPaths.length) {
                existingMediaFiles = mediaPaths;
                setMediaType('image');
                updateMediaPreview(null, mediaPaths);
            } else {
                existingMediaFiles = [];
                setMediaType('text');
            }
            window.scrollTo({ top:0, behavior:'smooth' });
        }

        function delT(id) {
            showConfirm('¿Eliminar esta regla permanentemente?', async (confirmed) => {
                if (!confirmed) return;
                try {
                    const res = await fetch('/api/train/'+id, { method:'DELETE' });
                    const data = await res.json();
                    if (data.ok) { showToast('Regla eliminada', 'success'); }
                    else showToast('Error al eliminar', 'error');
                } catch (e) { showToast('Error', 'error'); }
            });
        }

        async function saveRem() {
            const data = {
                id: document.getElementById('r-id').value,
                name: document.getElementById('r-name').value,
                phone: document.getElementById('r-phone').value,
                message: document.getElementById('r-msg').value,
                freq: document.getElementById('r-freq').value,
                date: document.getElementById('r-date').value
            };
            if (!data.name || !data.phone || !data.message || !data.date) { showToast('Completa todos los campos', 'warning'); return; }
            try {
                const res = await fetch('/api/reminders', { method:'POST', headers:{'Content-Type':'application/json'}, body: JSON.stringify(data) });
                const result = await res.json();
                if (result.ok) {
                    showToast('Mensaje programado', 'success');
                    document.getElementById('r-id').value = '';
                    document.getElementById('r-name').value = '';
                    document.getElementById('r-phone').value = '';
                    document.getElementById('r-msg').value = '';
                    document.getElementById('r-date').value = '';
                } else showToast('Error al programar: ' + (result.error || 'desconocido'), 'error');
            } catch (e) { showToast('Error de red', 'error'); }
        }
        function editR(id) {
            const r = db.reminders.find(r => r.id == id);
            if (!r) return;
            document.getElementById('r-id').value = r.id;
            document.getElementById('r-name').value = r.name;
            document.getElementById('r-phone').value = r.phone;
            document.getElementById('r-msg').value = r.message;
            document.getElementById('r-freq').value = r.freq;
            document.getElementById('r-date').value = r.date;
            window.scrollTo({ top:0, behavior:'smooth' });
        }
        function delR(id) {
            showConfirm('¿Eliminar este recordatorio?', async (confirmed) => {
                if (!confirmed) return;
                try {
                    const res = await fetch('/api/reminders/'+id, { method:'DELETE' });
                    const data = await res.json();
                    if (data.ok) { showToast('Recordatorio eliminado', 'success'); }
                    else showToast('Error al eliminar', 'error');
                } catch (e) { showToast('Error', 'error'); }
            });
        }
        async function saveExcl() {
            const name = document.getElementById('e-name').value;
            const phone = document.getElementById('e-phone').value;
            if (!name || !phone) { showToast('Completa ambos campos', 'warning'); return; }
            try {
                const res = await fetch('/api/exclude', { method:'POST', headers:{'Content-Type':'application/json'}, body: JSON.stringify({ name, phone }) });
                const data = await res.json();
                if (data.ok) { showToast('Número excluido', 'success'); document.getElementById('e-name').value=''; document.getElementById('e-phone').value=''; }
                else showToast('Error al excluir', 'error');
            } catch (e) { showToast('Error', 'error'); }
        }
        function delE(id) {
            showConfirm('¿Remover esta exclusión?', async (confirmed) => {
                if (!confirmed) return;
                try {
                    const res = await fetch('/api/exclude/'+id, { method:'DELETE' });
                    const data = await res.json();
                    if (data.ok) { showToast('Exclusión removida', 'success'); }
                    else showToast('Error', 'error');
                } catch (e) { showToast('Error', 'error'); }
            });
        }

        async function saveCredentials() {
            const user = document.getElementById('conf-user').value;
            const pass = document.getElementById('conf-pass').value;
            if (!user && !pass) return;
            try {
                const res = await fetch('/api/config/credentials', { method:'POST', headers:{'Content-Type':'application/json'}, body: JSON.stringify({ user, pass }) });
                const data = await res.json();
                if (data.ok) { showToast('Credenciales guardadas. Re-login en 3s.', 'success'); setTimeout(() => location.href='/login', 3000); }
                else showToast('Error', 'error');
            } catch (e) { showToast('Error', 'error'); }
        }
        async function saveBackupPhone() {
            const phone = document.getElementById('conf-backup-phone').value.replace(/\D/g, '');
            try {
                const res = await fetch('/api/config/backup-phone', { method:'POST', headers:{'Content-Type':'application/json'}, body: JSON.stringify({ backupPhone: phone }) });
                const data = await res.json();
                if (data.ok) showToast('Número backup guardado', 'success');
                else showToast('Error', 'error');
            } catch (e) { showToast('Error', 'error'); }
        }
        async function saveBackupHour() {
            const hour = document.getElementById('conf-backup-hour').value.trim();
            if (!hour || !/^([0-1][0-9]|2[0-3]):[0-5][0-9]$/.test(hour)) { showToast('Formato inválido (HH:MM)', 'warning'); return; }
            try {
                const res = await fetch('/api/config/backup-hour', { method:'POST', headers:{'Content-Type':'application/json'}, body: JSON.stringify({ backupHour: hour }) });
                const data = await res.json();
                if (data.ok) {
                    showToast('Hora de backup guardada', 'success');
                    // Actualizar el campo localmente para reflejar el cambio
                    document.getElementById('conf-backup-hour').value = hour;
                    // También actualizar db.backupHour para que coincida
                    db.backupHour = hour;
                } else showToast('Error', 'error');
            } catch (e) { showToast('Error', 'error'); }
        }
        async function saveConfiguracionEnvio() {
            const delay = parseFloat(document.getElementById('response-delay').value);
            const interval = parseInt(document.getElementById('queue-interval').value);
            try {
                await fetch('/api/config/delay', { method:'POST', headers:{'Content-Type':'application/json'}, body: JSON.stringify({ delay }) });
                await fetch('/api/config/queue-interval', { method:'POST', headers:{'Content-Type':'application/json'}, body: JSON.stringify({ interval }) });
                showToast('Configuración guardada', 'success');
            } catch (e) { showToast('Error', 'error'); }
        }

        function downloadBackup() { window.location.href = '/api/backup/download'; }
        function downloadTemplate() { window.location.href = '/api/train/template'; }
        async function sendBackupManually() {
            const phone = document.getElementById('conf-backup-phone').value;
            if (!phone) { showToast('Define número backup primero', 'warning'); return; }
            showToast('Enviando backup...', 'info');
            try {
                const res = await fetch('/api/backup/send', { method:'POST' });
                const data = await res.json();
                if (data.ok) showToast('Copia enviada', 'success');
                else showToast('Error al enviar', 'error');
            } catch (e) { showToast('Error', 'error'); }
        }
        async function restoreBackup(input) {
            if (!input.files[0]) return;
            showConfirm('¿Restaurar backup? Sobrescribirá datos actuales.', async (confirmed) => {
                if (!confirmed) { input.value=''; return; }
                const fd = new FormData(); fd.append('backup', input.files[0]);
                try {
                    const res = await fetch('/api/backup/restore', { method:'POST', body: fd });
                    const data = await res.json();
                    if (data.ok) { showToast('Copia restaurada, recargando...', 'success'); setTimeout(() => location.reload(), 1500); }
                    else showToast('Error en restauración', 'error');
                } catch (e) { showToast('Error', 'error'); }
                input.value='';
            });
        }
        async function importTraining(input) {
            if (!input.files[0]) return;
            const fd = new FormData(); fd.append('file', input.files[0]);
            try {
                const res = await fetch('/api/train/import', { method:'POST', body: fd });
                const data = await res.json();
                if (data.ok) { showToast(`Importadas ${data.imported} reglas`, 'success'); }
                else showToast('Error al importar', 'error');
            } catch (e) { showToast('Error', 'error'); }
            input.value='';
        }
        async function logoutWA() {
            showConfirm('¿Desvincular WhatsApp?', async (confirmed) => {
                if (!confirmed) return;
                try {
                    await fetch('/api/logout-wa', { method:'POST' });
                    showToast('Desvinculando...', 'info');
                    setTimeout(() => location.reload(), 2000);
                } catch (e) { showToast('Error', 'error'); }
            });
        }
        function logout() { location.href = '/login'; }

        async function load() {
            try {
                const res = await fetch('/api/data');
                if (res.status === 401) { location.href = '/login'; return; }
                const data = await res.json();
                db = data;
                document.getElementById('conf-backup-phone').value = data.backupPhone || '';
                document.getElementById('conf-backup-hour').value = data.backupHour || '12:00';
                document.getElementById('response-delay').value = data.responseDelay || 0;
                document.getElementById('delay-value').textContent = (data.responseDelay || 0).toFixed(1) + ' s';
                document.getElementById('queue-interval').value = data.queueInterval || 3000;
                document.getElementById('interval-value').textContent = (data.queueInterval || 3000) + ' ms';
                if (data.qrImage) {
                    document.getElementById('qr-img').innerHTML = `<img src="${data.qrImage}" class="w-full h-full object-contain rounded-2xl">`;
                }
                render();
                lucide.createIcons();
                setupContactSearch();
                const now = new Date();
                document.getElementById('clock-time').textContent = format12Hour(now);
                document.getElementById('clock-date').textContent = now.toLocaleDateString('es-ES', { timeZone:'America/Santo_Domingo', weekday:'long', year:'numeric', month:'long', day:'numeric' });
            } catch (e) {
                showToast('Error al cargar datos: '+e.message, 'error');
            }
        }

        function renderWeeklyChart(totalMsgs) {
            const base = totalMsgs || 0;
            const distribution = { lun: Math.round(base*0.16), mar: Math.round(base*0.18), mie: Math.round(base*0.13), jue: Math.round(base*0.21), vie: Math.round(base*0.24), sab: Math.round(base*0.05), dom: Math.round(base*0.03) };
            const maxDayVal = Math.max(...Object.values(distribution), 10);
            document.getElementById('y-max-val').textContent = `${maxDayVal} msgs`;
            document.getElementById('y-mid-val').textContent = `${Math.round(maxDayVal/2)} msgs`;
            document.getElementById('weekly-aggregate-total').textContent = `Total: ${base} msgs`;
            ['lun','mar','mie','jue','vie','sab','dom'].forEach(day => {
                const dayVal = distribution[day];
                const pct = Math.max(Math.round((dayVal/maxDayVal)*100), 10);
                const bar = document.getElementById(`bar-${day}`);
                const tip = document.getElementById(`tip-${day}`);
                const val = document.getElementById(`val-${day}`);
                if (bar) bar.style.height = `${pct}%`;
                if (tip) tip.textContent = `${dayVal} msgs`;
                if (val) val.textContent = dayVal;
            });
        }

        function render() {
            if (rendering) return;
            rendering = true;
            requestAnimationFrame(() => {
                const totalMessages = db.stats?.total || 0;
                document.getElementById('s-replied').textContent = db.stats?.replied || 0;
                document.getElementById('s-total').textContent = totalMessages;
                const today = new Date().toISOString().slice(0,10);
                const todayCount = (db.reminders || []).filter(r => r.date.startsWith(today)).length;
                document.getElementById('today-reminders-count').textContent = todayCount;
                renderWeeklyChart(totalMessages);

                const upcomingRemindersContainer = document.getElementById('dashboard-upcoming-reminders');
                const activeReminders = (db.reminders || []).filter(r => new Date(r.date) >= new Date()).sort((a,b) => new Date(a.date)-new Date(b.date)).slice(0,3);
                upcomingRemindersContainer.innerHTML = activeReminders.length ? activeReminders.map(r => {
                    const rawDate = new Date(r.date);
                    const dateString = rawDate.toLocaleDateString('es-ES', { month:'short', day:'numeric' });
                    let hours = rawDate.getHours();
                    const minutes = String(rawDate.getMinutes()).padStart(2,'0');
                    const ampm = hours >= 12 ? 'PM' : 'AM';
                    hours = hours % 12 || 12;
                    const timeString = `${hours}:${minutes} ${ampm}`;
                    return `
                        <div class="p-3 bg-zinc-950/50 border border-white/[0.02] rounded-xl flex items-center justify-between gap-3">
                            <div class="truncate">
                                <h4 class="text-xs font-bold text-zinc-200 truncate">${escapeHtml(r.name)}</h4>
                                <p class="text-[10px] text-zinc-500 mt-0.5 truncate">+${r.phone}</p>
                            </div>
                            <div class="text-right shrink-0">
                                <span class="inline-block px-2 py-0.5 bg-green-500/10 text-green-400 font-bold font-mono text-[9px] rounded-md">${dateString}, ${timeString}</span>
                            </div>
                        </div>
                    `;
                }).join('') : '<div class="text-center py-8 text-xs text-zinc-500 font-semibold">No hay envíos pendientes</div>';

                document.getElementById('l-train').innerHTML = (db.training || []).map(t => {
                    const mediaPaths = t.mediaPaths ? JSON.parse(t.mediaPaths) : [];
                    let mediaRender = '';
                    if (mediaPaths.length) {
                        mediaRender = `
                            <div class="flex flex-wrap gap-2 mt-3">
                                ${mediaPaths.map(p => {
                                    const isVideo = p.match(/\.(mp4|3gp|avi|mov)$/i);
                                    if (isVideo) {
                                        return `<video src="${p}" muted class="w-12 h-12 object-cover rounded-lg border border-white/10"></video>`;
                                    }
                                    return `<img src="${p}" class="w-12 h-12 object-cover rounded-lg border border-white/10" onerror="this.style.display='none'">`;
                                }).join('')}
                            </div>
                        `;
                    }
                    return `
                        <div class="glass-card p-5 rounded-2xl flex flex-col justify-between">
                            <div class="flex justify-between items-start">
                                <div>
                                    <span class="px-2.5 py-1 bg-green-500/10 text-green-400 text-[10px] font-bold rounded-lg uppercase tracking-wider">Regla (ID: ${t.id})</span>
                                    <h4 class="text-base font-bold text-white mt-2">"${escapeHtml(t.key)}"</h4>
                                    <p class="text-xs text-zinc-400 mt-2 italic leading-relaxed">"${escapeHtml(t.response)}"</p>
                                    ${mediaRender}
                                </div>
                                <div class="flex items-center gap-1">
                                    <button onclick="editT(${t.id})" class="p-1.5 text-zinc-400 hover:text-white rounded hover:bg-white/5"><i data-lucide="edit-3" class="w-4 h-4"></i></button>
                                    <button onclick="delT(${t.id})" class="p-1.5 text-red-400 hover:text-red-350 rounded hover:bg-red-500/10"><i data-lucide="trash-2" class="w-4 h-4"></i></button>
                                </div>
                            </div>
                        </div>
                    `;
                }).join('');

                document.getElementById('l-rem').innerHTML = (db.reminders || []).map(r => {
                    const rawDate = new Date(r.date);
                    const datePart = rawDate.toLocaleDateString('es-ES', { year:'numeric', month:'numeric', day:'numeric' });
                    let hours = rawDate.getHours();
                    const minutes = String(rawDate.getMinutes()).padStart(2,'0');
                    const ampm = hours >= 12 ? 'PM' : 'AM';
                    hours = hours % 12 || 12;
                    const formattedTime = `${hours}:${minutes} ${ampm}`;
                    return `
                        <div class="glass-card p-5 rounded-2xl border-l-4 border-l-green-500">
                            <div class="flex justify-between items-start mb-2">
                                <div>
                                    <span class="text-[10px] text-zinc-500 font-bold uppercase tracking-wider">${r.freq}</span>
                                    <h4 class="text-sm font-bold text-white mt-1">${escapeHtml(r.name)} (${r.phone})</h4>
                                </div>
                                <div class="flex items-center gap-1">
                                    <button onclick="editR(${r.id})" class="p-1.5 text-zinc-400 hover:text-white rounded hover:bg-white/5"><i data-lucide="edit-3" class="w-4 h-4"></i></button>
                                    <button onclick="delR(${r.id})" class="p-1.5 text-red-400 hover:text-red-350 rounded hover:bg-red-500/10"><i data-lucide="trash-2" class="w-4 h-4"></i></button>
                                </div>
                            </div>
                            <p class="text-xs text-zinc-400 italic mb-2">"${escapeHtml(r.message)}"</p>
                            <div class="text-[10px] text-zinc-500 font-bold font-mono">📅 Próximo envío: ${datePart} a las ${formattedTime}</div>
                        </div>
                    `;
                }).join('');

                document.getElementById('l-excl').innerHTML = (db.excluded || []).map(e => `
                    <div class="flex justify-between items-center p-4 glass-card rounded-2xl">
                        <div>
                            <span class="text-xs font-bold text-white block">${escapeHtml(e.name)}</span>
                            <span class="text-[10px] text-zinc-500 mt-0.5 block font-mono">+${e.phone}</span>
                        </div>
                        <button onclick="delE(${e.id})" class="p-2 text-red-400 hover:bg-red-500/10 rounded-xl transition-all"><i data-lucide="user-minus" class="w-4.5 h-4.5"></i></button>
                    </div>
                `).join('');

                renderWebsites();
                lucide.createIcons();
                rendering = false;
            });
        }

        document.getElementById('response-delay').addEventListener('input', e =>
            document.getElementById('delay-value').textContent = parseFloat(e.target.value).toFixed(1) + ' s'
        );
        document.getElementById('queue-interval').addEventListener('input', e =>
            document.getElementById('interval-value').textContent = e.target.value + ' ms'
        );
        document.getElementById('media-preview').innerHTML = '<span class="text-xs text-zinc-500">No hay archivos seleccionados</span>';

        window.onload = load;
    </script>
</body>
</html>
HTMLEOF

# ============================================================
# 10. login.html
# ============================================================
echo "🔐 Generando login.html..."
cat <<'LOGINEOF' > views/login.html
<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
    <title>GZMBOT | Login</title>
    <script src="https://cdn.tailwindcss.com"></script>
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700;800;900&family=Outfit:wght@400;700;800;900&display=swap" rel="stylesheet">
    <style>
        body { background:#0c0c12; font-family:'Inter',sans-serif; display:flex; align-items:center; justify-content:center; min-height:100vh; padding:1rem; position:relative; overflow:hidden; margin:0; }
        .bg-waves { position:fixed; inset:0; z-index:-1; overflow:hidden; }
        .wave { position:absolute; border-radius:50%; background:radial-gradient(circle, rgba(110,231,183,0.20) 0%, transparent 70%); animation:waveMove 25s infinite ease-in-out alternate; width:700px; height:700px; top:-150px; left:-150px; filter:blur(25px); }
        .wave:nth-child(2) { width:900px; height:900px; bottom:-250px; right:-250px; top:auto; animation-duration:30s; animation-delay:-6s; background:radial-gradient(circle, rgba(52,211,153,0.15) 0%, transparent 70%); filter:blur(30px); }
        .wave:nth-child(3) { width:500px; height:500px; top:50%; left:50%; transform:translate(-50%,-50%); animation-duration:35s; animation-delay:-12s; background:radial-gradient(circle, rgba(110,231,183,0.12) 0%, transparent 70%); filter:blur(25px); }
        @keyframes waveMove { 0% { transform:translate(0,0) scale(1); } 33% { transform:translate(80px,-60px) scale(1.1); } 66% { transform:translate(-40px,80px) scale(0.9); } 100% { transform:translate(60px,-40px) scale(1.05); } }
        .glass-panel { background:rgba(12,12,18,0.75); backdrop-filter:blur(24px); border:1px solid rgba(52,211,153,0.08); border-radius:2.5rem; }
        .login-title { color:#ffffff; font-weight:900; }
        .login-sub { color:#34d399; font-weight:700; letter-spacing:0.35em; }
        input { background:rgba(0,0,0,0.5)!important; border:1px solid rgba(52,211,153,0.08)!important; color:white!important; border-radius:1.25rem!important; padding:1rem 1.25rem!important; outline:none; width:100%; transition:border .3s; }
        input:focus { border-color:#34d399!important; box-shadow:0 0 0 3px rgba(52,211,153,0.06); }
        .btn-premium { background:linear-gradient(135deg, #0d9488 0%, #10b981 50%, #34d399 100%)!important; box-shadow:0 8px 30px -6px rgba(52,211,153,0.25); transition:all 0.3s cubic-bezier(0.4,0,0.2,1); }
        .btn-premium:hover { transform:translateY(-2px); box-shadow:0 14px 38px -4px rgba(52,211,153,0.4); filter:brightness(1.05); }
        .btn-premium:active { transform:translateY(1px); }
        .login-island { max-width:400px; width:100%; margin:0 auto; }
    </style>
</head>
<body>
    <div class="bg-waves"><div class="wave"></div><div class="wave"></div><div class="wave"></div></div>
    <div class="glass-panel login-island p-8 sm:p-12 text-center shadow-2xl relative">
        <div class="inline-flex items-center justify-center w-16 h-16 rounded-2xl bg-green-600/10 border border-green-500/15 text-green-400 mb-5"><i data-lucide="bot" class="w-8 h-8 text-green-400"></i></div>
        <h1 class="text-3.5xl sm:text-4xl font-black tracking-tight font-outfit login-title">GZMBOT</h1>
        <p class="text-[10px] tracking-[0.35em] uppercase mt-2 login-sub">Administrative Panel</p>
        <form onsubmit="login(event)" class="space-y-4 mt-8">
            <input type="text" id="u" placeholder="Usuario maestro" required>
            <input type="password" id="p" placeholder="Contraseña de acceso" required>
            <div id="error-msg" class="hidden text-xs text-red-400 bg-red-500/10 border border-red-500/20 p-3 rounded-xl">Credenciales incorrectas, por favor verifica.</div>
            <button type="submit" class="w-full py-4 text-white font-extrabold rounded-2xl text-sm tracking-wide btn-premium">ACCEDER AL PANEL</button>
        </form>
        <p class="text-[10px] text-zinc-600 mt-8">GZMBOT Engine • RD</p>
    </div>
    <script src="https://unpkg.com/lucide@latest"></script>
    <script>
        lucide.createIcons();
        async function login(e) {
            e.preventDefault();
            const err = document.getElementById('error-msg');
            err.classList.add('hidden');
            const res = await fetch('/login', { method:'POST', headers:{'Content-Type':'application/json'}, body: JSON.stringify({ user: document.getElementById('u').value, pass: document.getElementById('p').value }) });
            const data = await res.json();
            if (data.ok) location.href = '/';
            else err.classList.remove('hidden');
        }
    </script>
</body>
</html>
LOGINEOF

# ============================================================
# 11. Instalación de dependencias NPM
# ============================================================
echo "📦 Instalando dependencias NPM..."
npm install --production --no-optional --no-audit --no-fund --loglevel=error \
    whatsapp-web.js \
    qrcode \
    express \
    socket.io \
    express-session \
    puppeteer \
    moment-timezone \
    multer \
    better-sqlite3

# ============================================================
# 12. PM2
# ============================================================
echo "⚙️ Configurando PM2..."
npm install -g pm2 --quiet
pm2 delete gzmbot 2>/dev/null || true
pm2 start app.js --name gzmbot --env TZ=America/Santo_Domingo --max-memory-restart 256M --max-restarts 10 --restart-delay 5000 --exp-backoff-restart-delay=1000
pm2 save
pm2 startup | tail -n 1

# ============================================================
# 13. Configurar Nginx (HTTP)
# ============================================================
echo "🌐 Configurando Nginx..."
rm -f /etc/nginx/sites-enabled/default
rm -f /etc/nginx/sites-available/default
mkdir -p /etc/nginx/sites-available /etc/nginx/sites-enabled

cat > /etc/nginx/sites-available/gzmbot <<EOF
server {
    listen 80;
    server_name $DOMAIN;
    client_max_body_size 10M;

    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_connect_timeout 300s;
        proxy_send_timeout 300s;
        proxy_read_timeout 300s;
        proxy_buffer_size 128k;
        proxy_buffers 4 256k;
        proxy_busy_buffers_size 256k;
    }

    location /socket.io/ {
        proxy_pass http://127.0.0.1:3000/socket.io/;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_read_timeout 86400s;
        proxy_send_timeout 86400s;
    }
}
EOF

ln -sf /etc/nginx/sites-available/gzmbot /etc/nginx/sites-enabled/
systemctl start nginx
nginx -t && systemctl reload nginx

# ============================================================
# 14. SSL con acme.sh (standalone)
# ============================================================
echo "🔒 Obteniendo certificado SSL (modo standalone)..."
systemctl stop nginx

export LE_WORKING_DIR="/root/.acme.sh"

if /root/.acme.sh/acme.sh --issue -d $DOMAIN --standalone --server zerossl --keylength ec-256 --force; then
    SSL_SUCCESS=1
else
    echo "⚠️ Falló con ZeroSSL, intentando con Let's Encrypt..."
    if /root/.acme.sh/acme.sh --issue -d $DOMAIN --standalone --server letsencrypt --keylength ec-256 --force; then
        SSL_SUCCESS=1
    else
        SSL_SUCCESS=0
    fi
fi

if [ $SSL_SUCCESS -eq 1 ]; then
    mkdir -p /etc/nginx/ssl
    /root/.acme.sh/acme.sh --install-cert -d $DOMAIN --ecc \
        --key-file /etc/nginx/ssl/$DOMAIN.key \
        --fullchain-file /etc/nginx/ssl/$DOMAIN.crt

    cat > /etc/nginx/sites-available/gzmbot <<EOF
server {
    listen 80;
    server_name $DOMAIN;
    return 301 https://\$server_name\$request_uri;
}

server {
    listen 443 ssl http2;
    server_name $DOMAIN;
    client_max_body_size 10M;

    ssl_certificate /etc/nginx/ssl/$DOMAIN.crt;
    ssl_certificate_key /etc/nginx/ssl/$DOMAIN.key;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers 'HIGH:!aNULL:!MD5';

    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_connect_timeout 300s;
        proxy_send_timeout 300s;
        proxy_read_timeout 300s;
        proxy_buffer_size 128k;
        proxy_buffers 4 256k;
        proxy_busy_buffers_size 256k;
    }

    location /socket.io/ {
        proxy_pass http://127.0.0.1:3000/socket.io/;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_read_timeout 86400s;
        proxy_send_timeout 86400s;
    }
}
EOF

    (crontab -l 2>/dev/null; echo "0 0 * * * /root/.acme.sh/acme.sh --cron --home /root/.acme.sh > /dev/null") | crontab -
    echo "✅ Certificado SSL instalado y cron de renovación configurado."
else
    echo "⚠️ No se pudo obtener certificado SSL. El sitio seguirá en HTTP."
fi

systemctl start nginx
nginx -t && systemctl reload nginx

# ============================================================
# 15. Crear comando 'gzm' con menú interactivo mejorado
# ============================================================
echo "🛠️ Creando comando 'gzm'..."
cat > /usr/local/bin/gzm <<'GZMENU'
#!/bin/bash
# ============================================================
# GZMBOT - Menú interactivo (v2)
# ============================================================
GZMBOT_DIR="$HOME/gzmbot"
CONFIG_FILE="$GZMBOT_DIR/config.json"
NGINX_SSL_DIR="/etc/nginx/ssl"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

if [ ! -d "$GZMBOT_DIR" ]; then
    echo -e "${RED}❌ GZMBOT no está instalado.${NC}"
    exit 1
fi

get_current_domain() {
    if [ -f /etc/nginx/sites-available/gzmbot ]; then
        grep -oP 'server_name\s+\K[^;]+' /etc/nginx/sites-available/gzmbot | head -1 | tr -d ' '
    else
        echo "desconocido"
    fi
}

get_current_user() {
    if [ -f "$CONFIG_FILE" ]; then
        grep -oP '"adminUser":\s*"\K[^"]+' "$CONFIG_FILE" | head -1
    else
        echo "desconocido"
    fi
}

show_menu() {
    clear
    echo -e "${GREEN}=============================================================${NC}"
    echo -e "${BLUE}  GZMBOT - Panel de Control${NC}"
    echo -e "${GREEN}=============================================================${NC}"
    echo -e " Dominio actual: ${YELLOW}$(get_current_domain)${NC}"
    echo -e " Usuario panel:  ${YELLOW}$(get_current_user)${NC}"
    echo -e " Hora backup:   ${YELLOW}$(grep -oP '"backupHour":\s*"\K[^"]+' "$CONFIG_FILE" 2>/dev/null || echo "12:00")${NC}"
    echo -e "${GREEN}=============================================================${NC}"
    echo -e " 1) Cambiar dominio (renovar SSL)"
    echo -e " 2) Cambiar usuario/contraseña del panel"
    echo -e " 3) Cambiar hora de backup automático"
    echo -e " 4) Ver estado del bot"
    echo -e " 5) Reiniciar el bot"
    echo -e " 6) Ver logs del bot"
    echo -e " 7) Salir"
    echo -e "${GREEN}=============================================================${NC}"
    read -p "Selecciona una opción [1-7]: " choice
    case $choice in
        1) change_domain ;;
        2) change_credentials ;;
        3) change_backup_hour ;;
        4) show_status ;;
        5) restart_bot ;;
        6) show_logs ;;
        7) echo "¡Hasta luego!"; exit 0 ;;
        *) echo -e "${RED}Opción inválida${NC}"; sleep 2; show_menu ;;
    esac
}

change_domain() {
    echo -e "${BLUE}▶️ Cambiar dominio${NC}"
    read -p "Nuevo dominio (ej. ejemplo.com): " NEW_DOMAIN
    if [ -z "$NEW_DOMAIN" ]; then
        echo -e "${RED}❌ Dominio no puede estar vacío${NC}"
        sleep 2
        show_menu
        return
    fi

    echo -e "🔄 Actualizando Nginx..."
    if [ -f /etc/nginx/sites-available/gzmbot ]; then
        sed -i "s/server_name .*/server_name $NEW_DOMAIN;/g" /etc/nginx/sites-available/gzmbot
        nginx -t && systemctl reload nginx
        echo -e "${GREEN}✅ Nginx actualizado a $NEW_DOMAIN${NC}"
    else
        echo -e "${RED}❌ No se encontró configuración de Nginx${NC}"
        sleep 2
        show_menu
        return
    fi

    echo -e "🔒 Obteniendo nuevo certificado SSL..."
    systemctl stop nginx
    export LE_WORKING_DIR="/root/.acme.sh"
    if /root/.acme.sh/acme.sh --issue -d $NEW_DOMAIN --standalone --server zerossl --keylength ec-256 --force; then
        mkdir -p /etc/nginx/ssl
        /root/.acme.sh/acme.sh --install-cert -d $NEW_DOMAIN --ecc \
            --key-file /etc/nginx/ssl/$NEW_DOMAIN.key \
            --fullchain-file /etc/nginx/ssl/$NEW_DOMAIN.crt
        sed -i "s|ssl_certificate /etc/nginx/ssl/.*.crt|ssl_certificate /etc/nginx/ssl/$NEW_DOMAIN.crt|g" /etc/nginx/sites-available/gzmbot
        sed -i "s|ssl_certificate_key /etc/nginx/ssl/.*.key|ssl_certificate_key /etc/nginx/ssl/$NEW_DOMAIN.key|g" /etc/nginx/sites-available/gzmbot
        echo -e "${GREEN}✅ Certificado SSL obtenido e instalado para $NEW_DOMAIN${NC}"
    else
        echo -e "${RED}❌ Falló la obtención del certificado. El sitio seguirá en HTTP.${NC}"
    fi
    systemctl start nginx
    nginx -t && systemctl reload nginx
    sleep 2
    show_menu
}

change_credentials() {
    echo -e "${BLUE}▶️ Cambiar usuario/contraseña del panel${NC}"
    read -p "Nuevo usuario: " NEW_USER
    if [ -z "$NEW_USER" ]; then
        echo -e "${RED}❌ Usuario no puede estar vacío${NC}"
        sleep 2
        show_menu
        return
    fi
    read -sp "Nueva contraseña: " NEW_PASS
    echo
    if [ -z "$NEW_PASS" ]; then
        echo -e "${RED}❌ Contraseña no puede estar vacía${NC}"
        sleep 2
        show_menu
        return
    fi

    if [ -f "$CONFIG_FILE" ]; then
        sed -i "s/\"adminUser\": \".*\"/\"adminUser\": \"$NEW_USER\"/g" "$CONFIG_FILE"
        sed -i "s/\"adminPassword\": \".*\"/\"adminPassword\": \"$NEW_PASS\"/g" "$CONFIG_FILE"
        echo -e "${GREEN}✅ Credenciales actualizadas correctamente${NC}"
        echo -e "➡️  Reinicia el bot para que los cambios surtan efecto."
    else
        echo -e "${RED}❌ No se encontró el archivo de configuración${NC}"
    fi
    sleep 2
    show_menu
}

change_backup_hour() {
    echo -e "${BLUE}▶️ Cambiar hora de backup automático${NC}"
    read -p "Nueva hora (HH:MM, 24h): " NEW_HOUR
    if ! [[ "$NEW_HOUR" =~ ^([0-1][0-9]|2[0-3]):[0-5][0-9]$ ]]; then
        echo -e "${RED}❌ Formato inválido. Use HH:MM (ej. 12:00)${NC}"
        sleep 2
        show_menu
        return
    fi
    if [ -f "$CONFIG_FILE" ]; then
        sed -i "s/\"backupHour\": \".*\"/\"backupHour\": \"$NEW_HOUR\"/g" "$CONFIG_FILE"
        echo -e "${GREEN}✅ Hora de backup actualizada a $NEW_HOUR${NC}"
        echo -e "➡️  Reinicia el bot para aplicar el cambio."
    else
        echo -e "${RED}❌ No se encontró el archivo de configuración${NC}"
    fi
    sleep 2
    show_menu
}

show_status() {
    echo -e "${BLUE}▶️ Estado del bot${NC}"
    pm2 status gzmbot
    echo ""
    echo -e "🔗 Panel: http://$(get_current_domain) (o https si SSL está activo)"
    echo -e "Presiona Enter para volver..."
    read
    show_menu
}

restart_bot() {
    echo -e "${BLUE}▶️ Reiniciando bot...${NC}"
    pm2 restart gzmbot
    pm2 save
    echo -e "${GREEN}✅ Bot reiniciado${NC}"
    sleep 2
    show_menu
}

show_logs() {
    echo -e "${BLUE}▶️ Mostrando logs (presiona Ctrl+C para salir)${NC}"
    pm2 logs gzmbot --lines 30
    echo -e "\nPresiona Enter para volver..."
    read
    show_menu
}

show_menu
GZMENU

chmod +x /usr/local/bin/gzm

# ============================================================
# 16. Reiniciar PM2
# ============================================================
pm2 restart gzmbot || pm2 start app.js --name gzmbot --env TZ=America/Santo_Domingo --max-memory-restart 256M --max-restarts 10 --restart-delay 5000 --exp-backoff-restart-delay=1000
pm2 save

# ============================================================
# FIN
# ============================================================
echo ""
echo "============================================================="
echo -e "${GREEN}  GZMBOT - INSTALACIÓN COMPLETADA (v8)${NC}"
echo "============================================================="
if [ $SSL_SUCCESS -eq 1 ]; then
    echo -e "🔒 Panel seguro: ${GREEN}https://$DOMAIN${NC}"
else
    echo -e "🌐 Panel (sin SSL): ${YELLOW}http://$DOMAIN${NC}"
fi
echo -e "👤 Usuario: ${GREEN}$ADMIN_USER${NC}"
echo -e "🕒 Zona horaria: America/Santo_Domingo"
echo -e "📱 Espera 10-15 segundos para que el QR aparezca."
echo -e "💡 Ejecuta ${YELLOW}gzm${NC} para abrir el menú de gestión."
echo "============================================================="