"""生成爱乐之城 0.2.3 版（2026-11-26）四语言 × 三设备共 48 张 App Store 宣传图与验收清单。"""
import base64
import hashlib
import json
import struct
import subprocess
import tempfile
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
OUT_DIR = ROOT / "marketing" / "app-store-2026-11-26"
HERO_PIANO_PATH = OUT_DIR / "sources" / "hero-piano.jpg"
ARTIFACT_DIR = Path(r"C:\Users\Administrator\.gemini\antigravity\brain\64bb20fc-c8ac-4310-b8f4-edbfe55dff0b")
EDGE = r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"

DEVICES = {
    "iphone-medium": {"vw": 402, "vh": 874, "scale": 3, "width": 1206, "height": 2622},
    "iphone-duo": {"vw": 466, "vh": 678, "scale": 3, "width": 1398, "height": 2034},
    "ipad-13": {"vw": 1032, "vh": 1376, "scale": 2, "width": 2064, "height": 2752},
}

POSTER_SPECS = [
    {"slug": "01-aiyue-20261126-discovery", "theme": "teal", "active_tab": 0},
    {"slug": "02-aiyue-20261126-vinyl", "theme": "blue", "active_tab": 0},
    {"slug": "03-aiyue-20261126-classic", "theme": "silver", "active_tab": 0},
    {"slug": "04-aiyue-20261126-search", "theme": "indigo", "active_tab": 2},
]

LOCALE_CONTENT = {
    "zh-Hans": {
        "brand": "爱乐之城",
        "font_stack": '"Microsoft YaHei UI", "PingFang SC", "Segoe UI", sans-serif',
        "status_brand": "AiYue City",
        "tabs": ["首页", "音乐库", "搜索", "我的"],
        "posters": [
            {
                "title": "懂你的首页，越听越合拍",
                "subhead": "端侧口味推荐 · 每日精选 · 无限续播",
            },
            {
                "title": "黑胶沉浸，上推顺滑切曲",
                "subhead": "封面黑胶切换 · 居中同步歌词 · 跟手切歌",
            },
            {
                "title": "复古转盘，掌心重现",
                "subhead": "全屏金属机身 · 转盘触感操控 · 长按换肤",
            },
            {
                "title": "多源速搜，无损曲库随行",
                "subhead": "联想搜索试听 · 本地无损导入 · 统一收藏",
            },
        ],
        "home": {
            "greeting": "晚上好",
            "subtitle": "为你推荐好音乐",
            "badge": "今日推荐",
            "hero_title": "珊瑚海（钢琴版）",
            "hero_artist": "林暮弦乐团 · 精选推荐",
            "play": "播放",
            "shortcuts": ["热门榜单", "精选歌单", "风格电台", "最近收录"],
            "discover": "继续发现",
            "play_all": "播放全部",
            "peek_titles": ["深夜钢琴", "晴空慢旅", "柔光夜晚"],
            "rows": [
                ("海风与旧吉他", "陈屿 · 每日精选", "#008A82,#2563eb", "海"),
                ("夜雨声慢", "苏晚晴 · 舒缓钢琴", "#6366f1,#0ea5e9", "夜"),
                ("晴日慢行诗", "周默 · 原声吉他", "#d97757,#63438f", "晴"),
                ("微光森林", "顾川 · 独立民谣", "#059669,#0d9488", "森"),
                ("城市霓虹边", "安然 · 轻电子", "#8b5cf6,#ec4899", "霓"),
                ("写给夏天的信", "林弦 · 治愈纯音", "#f59e0b,#dc2626", "夏"),
            ],
            "mini_title": "海风与旧吉他",
            "mini_sub": "陈屿",
        },
        "player": {
            "tab_song": "歌曲",
            "tab_lyrics": "歌词",
            "track_title": "夜色慢行",
            "track_sub": "林暮 · 精选曲库",
            "synced_title": "同步歌词",
            "queue_title": "播放队列",
            "now_playing": "正在播放",
            "classic_title": "城市微光",
            "classic_artist": "周默",
            "classic_source": "无损曲库",
            "classic_lyric": "把今天的喜欢慢慢放进歌里",
            "lyrics": [
                ("城市的风吹过灯火边缘", False),
                ("有人把心事写进琴键", False),
                ("晚风经过安静的街", True),
                ("耳边是熟悉的旋律", False),
                ("把今天慢慢收进歌里", False),
                ("让心情随黑胶一直旋转", False),
                ("直到星光落在窗前", False),
            ],
            "queue": [
                ("城市微光", "周默"),
                ("海风与旧吉他", "陈屿"),
                ("珊瑚海（钢琴版）", "林暮弦乐团"),
                ("晴日慢行诗", "周默"),
                ("夜雨声慢", "苏晚晴"),
                ("写给夏天的信", "林弦"),
                ("微光森林", "顾川"),
            ],
        },
        "search": {
            "nav_title": "搜索",
            "query": "晚风",
            "button": "搜索",
            "chips": ["全部", "可试听", "热门曲库", "全球试听", "开放曲库"],
            "short_badge": "30秒试听",
            "rows": [
                ("晚风吹过旧街口", "林暮", "精选曲库 · 在线试听", True, False, False, False, "#008A82,#1e3a8a", "晚"),
                ("Midnight Breeze", "Aoi Piano", "全球试听 · 30秒片段", False, False, False, True, "#f59e0b,#db2777", "M"),
                ("Evening Wind (Acoustic)", "Clara Lin", "Jamendo · CC BY", False, True, False, False, "#10b981,#0f766e", "E"),
                ("晴空序曲", "爱乐之城", "Archive · 公有领域", False, True, True, False, "#6366f1,#3b82f6", "晴"),
                ("城市微光 (Live)", "周默", "精选曲库 · 在线试听", False, False, False, False, "#ec4899,#7e22ce", "城"),
            ],
        },
    },
    "zh-Hant": {
        "brand": "愛樂之城",
        "font_stack": '"Microsoft JhengHei UI", "PingFang TC", "Microsoft YaHei UI", sans-serif',
        "status_brand": "AiYue City",
        "tabs": ["首頁", "音樂庫", "搜尋", "我的"],
        "posters": [
            {
                "title": "懂你的首頁，越聽越合拍",
                "subhead": "裝置端品味推薦 · 每日精選 · 無限續播",
            },
            {
                "title": "黑膠沉浸，上推順滑切曲",
                "subhead": "封面黑膠切換 · 置中同步歌詞 · 跟手切歌",
            },
            {
                "title": "復古轉盤，掌心重現",
                "subhead": "全螢幕金屬機身 · 轉盤觸感操控 · 長按換膚",
            },
            {
                "title": "多源速搜，無損曲庫隨行",
                "subhead": "聯想搜尋試聽 · 本機無損匯入 · 統一收藏",
            },
        ],
        "home": {
            "greeting": "晚上好",
            "subtitle": "為你推薦好音樂",
            "badge": "今日推薦",
            "hero_title": "珊瑚海（鋼琴版）",
            "hero_artist": "林暮弦樂團 · 精選推薦",
            "play": "播放",
            "shortcuts": ["熱門榜單", "精選歌單", "風格電台", "最近收錄"],
            "discover": "繼續探索",
            "play_all": "播放全部",
            "peek_titles": ["深夜鋼琴", "晴空慢旅", "柔光夜晚"],
            "rows": [
                ("海風與舊吉他", "陳嶼 · 每日精選", "#008A82,#2563eb", "海"),
                ("夜雨聲慢", "蘇晚晴 · 舒緩鋼琴", "#6366f1,#0ea5e9", "夜"),
                ("晴日慢行詩", "周默 · 原聲吉他", "#d97757,#63438f", "晴"),
                ("微光森林", "顧川 · 獨立民謠", "#059669,#0d9488", "森"),
                ("城市霓虹邊", "安然 · 輕電子", "#8b5cf6,#ec4899", "霓"),
                ("寫給夏天的信", "林弦 · 治癒純音", "#f59e0b,#dc2626", "夏"),
            ],
            "mini_title": "海風與舊吉他",
            "mini_sub": "陳嶼",
        },
        "player": {
            "tab_song": "歌曲",
            "tab_lyrics": "歌詞",
            "track_title": "夜色慢行",
            "track_sub": "林暮 · 精選曲庫",
            "synced_title": "同步歌詞",
            "queue_title": "播放佇列",
            "now_playing": "正在播放",
            "classic_title": "城市微光",
            "classic_artist": "周默",
            "classic_source": "無損曲庫",
            "classic_lyric": "把今天的喜歡慢慢放進歌裡",
            "lyrics": [
                ("城市的風吹過燈火邊緣", False),
                ("有人把心事寫進琴鍵", False),
                ("晚風經過安靜的街", True),
                ("耳邊是熟悉的旋律", False),
                ("把今天慢慢收進歌裡", False),
                ("讓心情隨黑膠一直旋轉", False),
                ("直到星光落在窗前", False),
            ],
            "queue": [
                ("城市微光", "周默"),
                ("海風與舊吉他", "陳嶼"),
                ("珊瑚海（鋼琴版）", "林暮弦樂團"),
                ("晴日慢行詩", "周默"),
                ("夜雨聲慢", "蘇晚晴"),
                ("寫給夏天的信", "林弦"),
                ("微光森林", "顧川"),
            ],
        },
        "search": {
            "nav_title": "搜尋",
            "query": "晚風",
            "button": "搜尋",
            "chips": ["全部", "可試聽", "熱門曲庫", "全球試聽", "開放曲庫"],
            "short_badge": "30秒試聽",
            "rows": [
                ("晚風吹過舊街口", "林暮", "精選曲庫 · 線上試聽", True, False, False, False, "#008A82,#1e3a8a", "晚"),
                ("Midnight Breeze", "Aoi Piano", "全球試聽 · 30秒片段", False, False, False, True, "#f59e0b,#db2777", "M"),
                ("Evening Wind (Acoustic)", "Clara Lin", "Jamendo · CC BY", False, True, False, False, "#10b981,#0f766e", "E"),
                ("晴空序曲", "愛樂之城", "Archive · 公有領域", False, True, True, False, "#6366f1,#3b82f6", "晴"),
                ("城市微光 (Live)", "周默", "精選曲庫 · 線上試聽", False, False, False, False, "#ec4899,#7e22ce", "城"),
            ],
        },
    },
    "en-US": {
        "brand": "La La Land",
        "font_stack": '"Segoe UI", "SF Pro Display", "Helvetica Neue", Arial, sans-serif',
        "status_brand": "AiYue City",
        "tabs": ["Home", "Library", "Search", "My Music"],
        "posters": [
            {
                "title": "Home Made For Your Taste",
                "subhead": "On-Device Picks · Daily Mixes · Endless Play",
            },
            {
                "title": "Vinyl Mode & Fluid Push-Up",
                "subhead": "Instant Skin Switch · Centered Lyrics · Smooth Next",
            },
            {
                "title": "Retro Wheel, Reimagined",
                "subhead": "Full-Screen Alloy · Tactile Click Wheel · Long-Press",
            },
            {
                "title": "Multi-Source Search & Lossless",
                "subhead": "Smart Suggestions · Local FLAC · Unified Favorites",
            },
        ],
        "home": {
            "greeting": "Good Evening",
            "subtitle": "Picked for your listening mood",
            "badge": "Today's Pick",
            "hero_title": "Coral Sea (Piano)",
            "hero_artist": "Serene Keys · Featured",
            "play": "Play",
            "shortcuts": ["Top Chart", "Mixes", "Radio", "Recent"],
            "discover": "Explore More",
            "play_all": "Play All",
            "peek_titles": ["Late Piano", "Clear Sky", "Soft Night"],
            "rows": [
                ("Sea Breeze Guitar", "Elena Yu · Daily Pick", "#008A82,#2563eb", "S"),
                ("Midnight Piano Mist", "Aoi Lin · Solo Piano", "#6366f1,#0ea5e9", "M"),
                ("Clear Day Acoustic", "Ethan Zhou · Acoustic", "#d97757,#63438f", "C"),
                ("Amber Forest", "Clara Lin · Indie Folk", "#059669,#0d9488", "A"),
                ("Neon Skyline", "Noah Gu · Chill Synth", "#8b5cf6,#ec4899", "N"),
                ("Letter to Summer", "Liam Chen · Instrumental", "#f59e0b,#dc2626", "L"),
            ],
            "mini_title": "Sea Breeze Guitar",
            "mini_sub": "Elena Yu",
        },
        "player": {
            "tab_song": "Song",
            "tab_lyrics": "Lyrics",
            "track_title": "Midnight Stroll",
            "track_sub": "Serene Keys · Lossless",
            "synced_title": "Synced Lyrics",
            "queue_title": "Queue",
            "now_playing": "Now Playing",
            "classic_title": "City Glow",
            "classic_artist": "Ethan Zhou",
            "classic_source": "Local Lossless",
            "classic_lyric": "Keep your favorite songs close tonight",
            "lyrics": [
                ("Evening breeze crosses quiet streets", False),
                ("Soft piano notes fill the room", False),
                ("Familiar melodies stay beside you", True),
                ("Every beat turns smoothly in time", False),
                ("Hold onto the calm of tonight", False),
                ("Let music carry the moment far", False),
                ("Until starlight meets the window", False),
            ],
            "queue": [
                ("City Glow", "Ethan Zhou"),
                ("Sea Breeze Guitar", "Elena Yu"),
                ("Coral Sea (Piano)", "Serene Keys"),
                ("Clear Day Acoustic", "Ethan Zhou"),
                ("Midnight Piano Mist", "Aoi Lin"),
                ("Letter to Summer", "Liam Chen"),
                ("Amber Forest", "Clara Lin"),
            ],
        },
        "search": {
            "nav_title": "Search",
            "query": "Evening breeze",
            "button": "Search",
            "chips": ["All", "Playable", "Open Music", "Global", "Archive"],
            "short_badge": "30s Preview",
            "rows": [
                ("Evening Breeze Walk", "Serene Keys · Stream", "Featured · Playable", True, False, False, False, "#008A82,#1e3a8a", "E"),
                ("Midnight Breeze", "Aoi Piano", "Global · 30s Preview", False, False, False, True, "#f59e0b,#db2777", "M"),
                ("Evening Wind (Acoustic)", "Clara Lin", "Jamendo · CC BY", False, True, False, False, "#10b981,#0f766e", "W"),
                ("Clear Sky Overture", "AiYue Ensemble", "Archive · Public Domain", False, True, True, False, "#6366f1,#3b82f6", "C"),
                ("City Glow (Live)", "Ethan Zhou", "Featured · Playable", False, False, False, False, "#ec4899,#7e22ce", "G"),
            ],
        },
    },
    "fr-FR": {
        "brand": "La La Land",
        "font_stack": '"Segoe UI", "SF Pro Display", "Helvetica Neue", Arial, sans-serif',
        "status_brand": "La La Land",
        "tabs": ["Accueil", "Biblio.", "Recherche", "Perso"],
        "posters": [
            {
                "title": "Un Accueil Selon Vos Goûts",
                "subhead": "Recommandations locales · Sélections · Lecture continue",
            },
            {
                "title": "Vinyle et Passage Fluide",
                "subhead": "Styles par appui long · Paroles centrées · Glisser",
            },
            {
                "title": "Molette Rétro Réinventée",
                "subhead": "Châssis métal plein écran · Commandes tactiles",
            },
            {
                "title": "Recherche Multi-Sources",
                "subhead": "Suggestions · Import sans perte · Favoris unifiés",
            },
        ],
        "home": {
            "greeting": "Bonsoir",
            "subtitle": "Sélection musicale pour vous",
            "badge": "Sélection",
            "hero_title": "Mer de Corail (Piano)",
            "hero_artist": "Atelier Nocturne · Coup de cœur",
            "play": "Lire",
            "shortcuts": ["Classement", "Sélections", "Radios", "Récents"],
            "discover": "À découvrir",
            "play_all": "Tout lire",
            "peek_titles": ["Piano Nuit", "Ciel Clair", "Nuit Douce"],
            "rows": [
                ("Brise Marine", "Éléna Yu · Sélection", "#008A82,#2563eb", "B"),
                ("Pluie d'Étoiles", "Aoi Lin · Piano seul", "#6366f1,#0ea5e9", "P"),
                ("Matin Acoustique", "Noé Zhou · Guitare", "#d97757,#63438f", "M"),
                ("Forêt Ambrée", "Clara Lin · Folk doux", "#059669,#0d9488", "F"),
                ("Lueur Urbaine", "Luc Gu · Électro doux", "#8b5cf6,#ec4899", "L"),
                ("Lettre d'Été", "Léo Chen · Instrumental", "#f59e0b,#dc2626", "E"),
            ],
            "mini_title": "Brise Marine",
            "mini_sub": "Éléna Yu",
        },
        "player": {
            "tab_song": "Chanson",
            "tab_lyrics": "Paroles",
            "track_title": "Balade Nocturne",
            "track_sub": "Atelier Nocturne · Sans perte",
            "synced_title": "Paroles synchronisées",
            "queue_title": "File d'attente",
            "now_playing": "À l'écoute",
            "classic_title": "Lueur de la Ville",
            "classic_artist": "Noé Zhou",
            "classic_source": "Audio local",
            "classic_lyric": "Gardez vos titres favoris tout près ce soir",
            "lyrics": [
                ("La brise du soir traverse la rue", False),
                ("Les notes de piano emplissent l'air", False),
                ("Une mélodie familière vous accompagne", True),
                ("Chaque refrain tourne en douceur", False),
                ("Gardez la paix de cet instant", False),
                ("Laissez la musique vous emporter", False),
                ("Jusqu'aux lumières de l'aurore", False),
            ],
            "queue": [
                ("Lueur de la Ville", "Noé Zhou"),
                ("Brise Marine", "Éléna Yu"),
                ("Mer de Corail (Piano)", "Atelier Nocturne"),
                ("Matin Acoustique", "Noé Zhou"),
                ("Pluie d'Étoiles", "Aoi Lin"),
                ("Lettre d'Été", "Léo Chen"),
                ("Forêt Ambrée", "Clara Lin"),
            ],
        },
        "search": {
            "nav_title": "Recherche",
            "query": "Brise du soir",
            "button": "Chercher",
            "chips": ["Tout", "Écoutables", "Sélection", "Global", "Archive"],
            "short_badge": "Extrait 30s",
            "rows": [
                ("Brise du Soir", "Atelier Nocturne", "Sélection · Écoutable", True, False, False, False, "#008A82,#1e3a8a", "B"),
                ("Midnight Breeze", "Aoi Piano", "Global · Extrait 30s", False, False, False, True, "#f59e0b,#db2777", "M"),
                ("Evening Wind (Acoustic)", "Clara Lin", "Jamendo · CC BY", False, True, False, False, "#10b981,#0f766e", "W"),
                ("Ouverture Ciel Clair", "La La Land", "Archive · Domaine public", False, True, True, False, "#6366f1,#3b82f6", "O"),
                ("Lueur Urbaine (Live)", "Noé Zhou", "Sélection · Écoutable", False, False, False, False, "#ec4899,#7e22ce", "L"),
            ],
        },
    },
}


def hero_piano_uri() -> str:
    data = HERO_PIANO_PATH.read_bytes()
    return "data:image/jpeg;base64," + base64.b64encode(data).decode("ascii")


def status_icons_svg(color: str) -> str:
    return f'''
    <div style="display:flex;align-items:center;gap:4px;">
      <svg width="13" height="9" viewBox="0 0 13 9" fill="{color}">
        <rect x="0" y="6" width="2" height="3" rx="0.6"/>
        <rect x="3.5" y="4.2" width="2" height="4.8" rx="0.6"/>
        <rect x="7" y="2.2" width="2" height="6.8" rx="0.6"/>
        <rect x="10.5" y="0" width="2" height="9" rx="0.6"/>
      </svg>
      <svg width="12" height="9" viewBox="0 0 12 9" fill="none" stroke="{color}" stroke-width="1.35" stroke-linecap="round">
        <path d="M1.2 3.2C3.9 0.9 8.1 0.9 10.8 3.2"/>
        <path d="M3.1 5.3C4.8 3.9 7.2 3.9 8.9 5.3"/>
        <circle cx="6" cy="7.5" r="0.9" fill="{color}" stroke="none"/>
      </svg>
      <svg width="18" height="9" viewBox="0 0 18 9" fill="none">
        <rect x="0.6" y="0.8" width="14.5" height="7.4" rx="2.2" stroke="{color}" stroke-opacity="0.45" stroke-width="1"/>
        <rect x="2" y="2.1" width="11.6" height="4.8" rx="1.2" fill="{color}"/>
        <path d="M16.2 3.1V5.9" stroke="{color}" stroke-opacity="0.45" stroke-width="1.3" stroke-linecap="round"/>
      </svg>
    </div>'''


def tab_icon_svg(index: int, color: str) -> str:
    if index == 0:
        return f'<svg width="15" height="15" viewBox="0 0 16 16" fill="{color}"><path d="M8 1.5L1.5 7h1.8v7h3.3V9.8h2.8V14h3.3V7h1.8z"/></svg>'
    if index == 1:
        return f'<svg width="15" height="15" viewBox="0 0 16 16" fill="{color}"><path d="M6 2.5v7.6a2.3 2.3 0 1 1-1.3-2V4.3L13 2.5v6.6a2.3 2.3 0 1 1-1.3-2V4L6 5.2z"/></svg>'
    if index == 2:
        return f'<svg width="15" height="15" viewBox="0 0 16 16" fill="none" stroke="{color}" stroke-width="1.7" stroke-linecap="round"><circle cx="7" cy="7" r="4.5"/><path d="M10.5 10.5L13.8 13.8"/></svg>'
    return f'<svg width="15" height="15" viewBox="0 0 16 16" fill="{color}"><circle cx="8" cy="5.5" r="2.6"/><path d="M3 13.5c.6-2.5 2.5-3.8 5-3.8s4.4 1.3 5 3.8z"/></svg>'


def canvas_backdrop_css(theme: str) -> str:
    if theme == "teal":
        return """
        .canvas {
          background: radial-gradient(circle at 76% 22%, rgba(0,150,136,0.28) 0%, rgba(9,20,24,0) 52%),
                      linear-gradient(168deg, #071015 0%, #0d2126 54%, #081217 100%);
        }
        .glow-arc.a1 { border: 2px solid rgba(0,196,180,0.28); box-shadow: 0 0 46px rgba(0,168,156,0.25), inset 0 0 40px rgba(0,168,156,0.16); }
        .glow-arc.a2 { border: 1.5px solid rgba(99,179,237,0.18); box-shadow: 0 0 38px rgba(56,189,248,0.14); }
        """
    if theme == "blue":
        return """
        .canvas {
          background: radial-gradient(circle at 25% 24%, rgba(59,130,246,0.32) 0%, rgba(10,14,28,0) 52%),
                      linear-gradient(168deg, #070912 0%, #0d1d34 55%, #070b14 100%);
        }
        .glow-arc.a1 { border: 2px solid rgba(96,165,250,0.28); box-shadow: 0 0 42px rgba(59,130,246,0.25); }
        .glow-arc.a2 { border: 1.5px solid rgba(0,180,170,0.24); box-shadow: 0 0 40px rgba(0,138,130,0.22); }
        """
    if theme == "silver":
        return """
        .canvas {
          background: radial-gradient(circle at 50% 24%, rgba(203,213,225,0.22) 0%, rgba(12,14,18,0) 52%),
                      linear-gradient(168deg, #0b0d12 0%, #1c2128 54%, #0b0d11 100%);
        }
        .glow-arc.a1 { border: 2px solid rgba(226,232,240,0.24); box-shadow: 0 0 42px rgba(148,163,184,0.20); }
        .glow-arc.a2 { border: 1.5px solid rgba(0,138,130,0.22); box-shadow: 0 0 36px rgba(0,138,130,0.16); }
        """
    return """
    .canvas {
      background: radial-gradient(circle at 75% 20%, rgba(99,102,241,0.30) 0%, rgba(12,14,28,0) 52%),
                  linear-gradient(168deg, #090b16 0%, #151b32 54%, #090c14 100%);
    }
    .glow-arc.a1 { border: 2px solid rgba(129,140,248,0.28); box-shadow: 0 0 44px rgba(99,102,241,0.22); }
    .glow-arc.a2 { border: 1.5px solid rgba(0,196,180,0.22); box-shadow: 0 0 38px rgba(0,168,156,0.18); }
    """


def compact_song_html(title: str, sub: str, grad: str, glyph: str, active: bool, cover_px: str, pad: str = "6px 8px") -> str:
    color = "#008A82" if active else "#141820"
    icon = (
        '<svg width="17" height="17" viewBox="0 0 18 18" fill="#008A82"><circle cx="9" cy="9" r="8"/><rect x="6.3" y="5.8" width="1.8" height="6.4" rx="0.6" fill="#fff"/><rect x="9.9" y="5.8" width="1.8" height="6.4" rx="0.6" fill="#fff"/></svg>'
        if active else
        '<svg width="17" height="17" viewBox="0 0 18 18" fill="none" stroke="#9aa3b2" stroke-width="1.3"><circle cx="9" cy="9" r="7.4"/><path d="M7.5 6.2l4.4 2.8-4.4 2.8z" fill="#9aa3b2" stroke="none"/></svg>'
    )
    return f'''
    <div style="display:flex;align-items:center;gap:9px;padding:{pad};border-radius:12px;background:rgba(255,255,255,0.82);border:0.5px solid rgba(255,255,255,0.95);box-shadow:0 2px 6px rgba(15,23,42,0.03);">
      <div style="width:{cover_px};height:{cover_px};border-radius:8px;flex-shrink:0;background:linear-gradient(135deg,{grad});display:flex;align-items:center;justify-content:center;color:rgba(255,255,255,0.94);font-size:13px;font-weight:800;">{glyph}</div>
      <div style="flex:1;min-width:0;">
        <div style="font-size:11px;font-weight:700;color:{color};white-space:nowrap;overflow:hidden;text-overflow:ellipsis;">{title}</div>
        <div style="font-size:8.6px;color:#64748b;margin-top:1.5px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;">{sub}</div>
      </div>
      {icon}
    </div>'''


def discovery_inner(device: str, loc: dict, piano_uri: str) -> str:
    h = loc["home"]
    compact = device == "iphone-duo"
    wide = device == "ipad-13"
    pad = "10px 14px 4px" if compact else ("12px 26px 8px" if wide else "8px 14px 4px")
    gap = "8px" if compact else ("15px" if wide else "11px")
    hero_h = "104px" if compact else ("220px" if wide else "134px")
    sc_size = "32px" if compact else ("52px" if wide else "38px")
    row_cover = "34px" if compact else ("48px" if wide else "40px")

    greet_fs = "32px" if wide else ("20px" if compact else "22.5px")
    sub_fs = "13.5px" if wide else ("9px" if compact else "10px")
    search_sz = "42px" if wide else ("28px" if compact else "32px")

    def shortcut_tile(label: str, svg_inner: str, fill_teal: bool) -> str:
        fill = "#008A82" if fill_teal else "none"
        ico = "22" if wide else ("15" if compact else "17")
        return f'''
        <div style="display:flex;flex-direction:column;align-items:center;gap:{"6px" if wide else "4px"};">
          <div style="width:{sc_size};height:{sc_size};border-radius:{"16px" if wide else "12px"};background:rgba(255,255,255,0.88);border:0.5px solid rgba(255,255,255,0.96);display:flex;align-items:center;justify-content:center;box-shadow:0 3px 8px rgba(15,23,42,0.05);">
            <svg width="{ico}" height="{ico}" viewBox="0 0 16 16" fill="{fill}">{svg_inner}</svg>
          </div>
          <div style="font-size:{"12px" if wide else ("7.8px" if compact else "8.8px")};font-weight:600;color:#1e293b;white-space:nowrap;">{label}</div>
        </div>'''

    if wide:
        col1 = "".join(compact_song_html(t, s, g, c, i == 0, row_cover, "9px 12px") for i, (t, s, g, c) in enumerate(h["rows"][:3]))
        col2 = "".join(compact_song_html(t, s, g, c, False, row_cover, "9px 12px") for t, s, g, c in h["rows"][3:6])
        peek_cards = [
            (h["peek_titles"][0], "#14b8a6,#1d4ed8", "♪"),
            (h["peek_titles"][1], "#f59e0b,#b45309", "☀"),
            (h["peek_titles"][2], "#6366f1,#312e81", "★"),
            (h["shortcuts"][1], "#ec4899,#7e22ce", "♥"),
            (h["shortcuts"][2], "#0ea5e9,#0f766e", "♫"),
        ]
        shelf_strip = f'''
        <div style="margin-top:2px;">
          <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:8px;">
            <span style="font-size:18px;font-weight:800;color:#121720;">{h["shortcuts"][1]}</span>
          </div>
          <div style="display:grid;grid-template-columns:repeat(5,1fr);gap:14px;">
            {"".join(f'<div style="height:108px;border-radius:16px;background:linear-gradient(135deg,{g});display:flex;flex-direction:column;justify-content:flex-end;padding:12px;color:#fff;font-weight:800;font-size:13.5px;box-shadow:0 6px 14px rgba(0,0,0,0.12);">{name}</div>' for name, g, _ in peek_cards)}
          </div>
        </div>'''
        discover_rows = f'''
        <div style="display:grid;grid-template-columns:1fr 1fr;gap:14px;">
          <div style="display:flex;flex-direction:column;gap:9px;">{col1}</div>
          <div style="display:flex;flex-direction:column;gap:9px;">{col2}</div>
        </div>
        {shelf_strip}'''
    else:
        col1_rows = "".join(compact_song_html(t, s, g, c, i == 0, row_cover, "5.5px 8px" if compact else "7px 9px") for i, (t, s, g, c) in enumerate(h["rows"][:3]))
        peek_cols = "".join(
            f'''<div style="height:{"46px" if compact else "54px"};border-radius:11px;background:rgba(255,255,255,0.82);padding:5px;display:flex;align-items:center;box-shadow:0 2px 6px rgba(15,23,42,0.03);">
                  <div style="width:{"34px" if compact else "40px"};height:{"34px" if compact else "40px"};border-radius:8px;background:linear-gradient(135deg,{g});display:flex;align-items:center;justify-content:center;color:#fff;font-weight:800;font-size:12px;">{c}</div>
                </div>'''
            for _, _, g, c in h["rows"][3:6]
        )
        bottom_peek = "".join(
            f'<div style="height:{"38px" if compact else "64px"};border-radius:12px;background:linear-gradient(135deg,{g});display:flex;align-items:flex-end;padding:7px 9px;color:rgba(255,255,255,0.92);font-size:9px;font-weight:700;opacity:0.92;">{name}</div>'
            for name, g, _ in [
                (h["peek_titles"][0], "#0f766e,#1e293b", "p"),
                (h["peek_titles"][1], "#475569,#1e293b", "s"),
                (h["peek_titles"][2], "#b45309,#7c2d12", "n"),
            ]
        )
        discover_rows = f'''
        <div style="display:grid;grid-template-columns:1fr {"42px" if compact else "50px"};gap:9px;overflow:hidden;margin-right:-14px;">
          <div style="display:flex;flex-direction:column;gap:{"6px" if compact else "7.5px"};">{col1_rows}</div>
          <div style="display:flex;flex-direction:column;gap:{"6px" if compact else "7.5px"};opacity:0.96;">{peek_cols}</div>
        </div>
        <div style="margin-top:{"2px" if compact else "4px"};">
          <div style="font-size:{"10.5px" if compact else "11.5px"};font-weight:800;color:#121720;margin-bottom:5px;">{h["shortcuts"][1]}</div>
          <div style="display:grid;grid-template-columns:repeat(3,1fr);gap:8px;">
            {bottom_peek}
          </div>
        </div>'''

    return f'''
    <div style="flex:1;padding:{pad};display:flex;flex-direction:column;gap:{gap};overflow:hidden;">
      <div style="display:flex;justify-content:space-between;align-items:center;">
        <div>
          <div style="font-size:{greet_fs};font-weight:800;color:#0f172a;line-height:1.1;letter-spacing:-0.4px;">{h["greeting"]}</div>
          <div style="font-size:{sub_fs};color:#64748b;margin-top:2px;">{h["subtitle"]}</div>
        </div>
        <div style="width:{search_sz};height:{search_sz};border-radius:50%;background:rgba(255,255,255,0.88);border:0.5px solid rgba(255,255,255,0.96);display:flex;align-items:center;justify-content:center;box-shadow:0 3px 10px rgba(15,23,42,0.06);">
          <svg width="{"17" if wide else "14"}" height="{"17" if wide else "14"}" viewBox="0 0 16 16" fill="none" stroke="#0f172a" stroke-width="1.9" stroke-linecap="round"><circle cx="7" cy="7" r="4.8"/><path d="M10.7 10.7L14 14"/></svg>
        </div>
      </div>

      <div style="position:relative;height:{hero_h};border-radius:{"22px" if wide else "18px"};overflow:hidden;box-shadow:0 12px 24px rgba(15,23,42,0.18);flex-shrink:0;">
        <img src="{piano_uri}" style="position:absolute;inset:0;width:100%;height:100%;object-fit:cover;object-position:center;" />
        <div style="position:absolute;inset:0;background:linear-gradient(180deg,rgba(12,10,9,0.05) 18%,rgba(12,10,9,0.78) 100%);"></div>
        <div style="position:absolute;left:{"22px" if wide else "14px"};right:{"22px" if wide else "14px"};bottom:{"18px" if wide else "11px"};display:flex;align-items:flex-end;justify-content:space-between;gap:10px;color:#fff;">
          <div style="min-width:0;flex:1;">
            <div style="display:inline-block;font-size:{"11px" if wide else "7.8px"};font-weight:700;padding:2.5px 8px;border-radius:99px;background:rgba(255,255,255,0.24);backdrop-filter:blur(6px);margin-bottom:4px;">{h["badge"]}</div>
            <div style="font-size:{"24px" if wide else ("13.5px" if compact else "15px")};font-weight:800;line-height:1.18;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;">{h["hero_title"]}</div>
            <div style="font-size:{"12.5px" if wide else "8.5px"};opacity:0.86;margin-top:2px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;">{h["hero_artist"]}</div>
          </div>
          <div style="display:inline-flex;align-items:center;gap:4px;padding:{"8px 16px" if wide else "5px 11px"};border-radius:99px;background:rgba(255,255,255,0.26);font-size:{"13px" if wide else "9px"};font-weight:700;flex-shrink:0;">
            <svg width="8" height="9" viewBox="0 0 10 12" fill="#fff"><path d="M1 1l8 5-8 5z"/></svg>{h["play"]}
          </div>
        </div>
      </div>

      <div style="display:grid;grid-template-columns:repeat(4,1fr);gap:{"14px" if wide else "6px"};">
        {shortcut_tile(h["shortcuts"][0], '<path d="M8 1.2c2.5 2.4 4.5 4.9 4.5 7.7A4.5 4.5 0 1 1 3.5 8.9c0-1.9 1-3.6 2.1-4.8.2 1.1.9 1.9 1.5 2.2-.3-1.7.1-3.6.9-5.1z"/>', True)}
        {shortcut_tile(h["shortcuts"][1], '<path d="M8 1.5l2 4.1 4.5.6-3.3 3.2.8 4.5L8 11.7l-4 2.2.8-4.5L1.5 6.2 6 5.6z"/>', True)}
        {shortcut_tile(h["shortcuts"][2], '<circle cx="8" cy="8" r="1.4" fill="#008A82"/><path d="M5.1 5.1a4.1 4.1 0 0 0 0 5.8M10.9 5.1a4.1 4.1 0 0 1 0 5.8M2.8 2.8a7.4 7.4 0 0 0 0 10.4M13.2 2.8a7.4 7.4 0 0 1 0 10.4" fill="none" stroke="#008A82" stroke-width="1.5" stroke-linecap="round"/>', False)}
        {shortcut_tile(h["shortcuts"][3], '<path d="M8 1l1.5 4.2L13.8 6l-3.6 2.5 1.1 4.3L8 10.4 4.7 12.8l1.1-4.3L2.2 6l4.3-.8z"/>', True)}
      </div>

      <div>
        <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:{"8px" if wide else "5px"};">
          <span style="font-size:{"18px" if wide else ("12px" if compact else "13.5px")};font-weight:800;color:#0f172a;">{h["discover"]}</span>
          <span style="display:inline-flex;align-items:center;gap:4px;padding:{"5px 12px" if wide else "4px 9px"};border-radius:99px;background:rgba(255,255,255,0.86);font-size:{"11.5px" if wide else "8.5px"};font-weight:700;color:#0f172a;box-shadow:0 2px 6px rgba(15,23,42,0.04);">
            <svg width="7" height="8" viewBox="0 0 10 12" fill="#0f172a"><path d="M1 1l8 5-8 5z"/></svg>{h["play_all"]}
          </span>
        </div>
        {discover_rows}
      </div>
    </div>'''


def vinyl_svg(size: int) -> str:
    grooves = "".join(
        f'<circle cx="115" cy="115" r="{r}" fill="none" stroke="rgba(255,255,255,0.065)" stroke-width="0.9"/>'
        for r in range(52, 110, 6)
    )
    return f'''
    <div style="position:relative;width:{size}px;height:{size}px;display:flex;align-items:center;justify-content:center;">
      <div style="position:absolute;inset:4px;border-radius:50%;background:radial-gradient(circle,rgba(0,180,170,0.42) 0%,rgba(0,138,130,0) 70%);"></div>
      <svg width="{size}" height="{size}" viewBox="0 0 230 230" style="filter:drop-shadow(0 12px 18px rgba(0,0,0,0.42));">
        <defs>
          <radialGradient id="disc" cx="50%" cy="50%" r="50%"><stop offset="0%" stop-color="#050608"/><stop offset="100%" stop-color="#171920"/></radialGradient>
          <linearGradient id="labelArt" x1="0" y1="0" x2="1" y2="1"><stop offset="0%" stop-color="#ff9966"/><stop offset="50%" stop-color="#ff5e62"/><stop offset="100%" stop-color="#3a7bd5"/></linearGradient>
          <linearGradient id="arm" x1="0" y1="0" x2="1" y2="0"><stop offset="0%" stop-color="#ffffff"/><stop offset="50%" stop-color="#9ca3af"/><stop offset="100%" stop-color="#ffffff"/></linearGradient>
        </defs>
        <circle cx="115" cy="115" r="106" fill="url(#disc)"/>
        {grooves}
        <circle cx="115" cy="115" r="44" fill="url(#labelArt)" stroke="rgba(0,0,0,0.85)" stroke-width="3.5"/>
        <circle cx="115" cy="115" r="6" fill="#008A82"/>
        <g transform="translate(150, 8)">
          <path d="M52 12 Q62 56 18 92" fill="none" stroke="url(#arm)" stroke-width="4.5" stroke-linecap="round"/>
          <rect x="11" y="84" width="10" height="20" rx="4" transform="rotate(38 16 94)" fill="#ffffff"/>
          <circle cx="52" cy="12" r="10" fill="#9ca3af" stroke="rgba(255,255,255,0.65)" stroke-width="1.5"/>
        </g>
      </svg>
    </div>'''


def now_playing_controls_html(loc: dict, wide: bool = False) -> str:
    p = loc["player"]
    fs_title = "20px" if wide else "15px"
    fs_art = "13px" if wide else "10.5px"
    play_sz = "60px" if wide else "48px"
    return f'''
    <div style="display:flex;flex-direction:column;gap:{"14px" if wide else "11px"};width:100%;">
      <div style="display:flex;align-items:center;justify-content:space-between;">
        <div style="min-width:0;">
          <div style="font-size:{fs_title};font-weight:800;color:#fff;">{p["track_title"]}</div>
          <div style="font-size:{fs_art};color:rgba(255,255,255,0.72);margin-top:2px;">{p["track_sub"]}</div>
        </div>
        <div style="display:flex;align-items:center;gap:12px;">
          <svg width="19" height="19" viewBox="0 0 20 20" fill="#ff4f8b"><path d="M10 17.2l-1.3-1.2C4.1 11.8 1.5 9.4 1.5 6.4 1.5 4 3.4 2.2 5.7 2.2c1.4 0 2.7.7 3.5 1.8.8-1.1 2.1-1.8 3.5-1.8 2.3 0 4.2 1.8 4.2 4.2 0 3-2.6 5.4-7.2 9.6L10 17.2z"/></svg>
          <svg width="19" height="19" viewBox="0 0 20 20" fill="none" stroke="rgba(255,255,255,0.85)" stroke-width="1.5"><circle cx="10" cy="10" r="7.5"/><circle cx="6.8" cy="10" r="0.9" fill="#fff" stroke="none"/><circle cx="10" cy="10" r="0.9" fill="#fff" stroke="none"/><circle cx="13.2" cy="10" r="0.9" fill="#fff" stroke="none"/></svg>
        </div>
      </div>
      <div>
        <div style="height:4px;border-radius:2px;background:rgba(255,255,255,0.24);overflow:hidden;">
          <div style="width:38%;height:100%;background:rgba(255,255,255,0.92);border-radius:2px;"></div>
        </div>
        <div style="display:flex;justify-content:space-between;margin-top:5px;font-size:{"11px" if wide else "9px"};color:rgba(255,255,255,0.68);font-variant-numeric:tabular-nums;">
          <span>01:24</span><span>03:58</span>
        </div>
      </div>
      <div style="display:flex;align-items:center;justify-content:space-between;padding:2px 4px;">
        <svg width="18" height="18" viewBox="0 0 18 18" fill="none" stroke="rgba(255,255,255,0.82)" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><path d="M13 3l2.5 2.5L13 8M3 9V7.5a2 2 0 0 1 2-2h10.5M5 15l-2.5-2.5L5 10M15 9v1.5a2 2 0 0 1-2 2H2.5"/></svg>
        <svg width="21" height="21" viewBox="0 0 20 20" fill="#fff"><path d="M9.5 10L17 5v10l-7.5-5zM2 10l7.5-5v10L2 10z"/></svg>
        <div style="width:{play_sz};height:{play_sz};border-radius:50%;background:#008A82;display:flex;align-items:center;justify-content:center;box-shadow:0 8px 18px rgba(0,0,0,0.28);">
          <svg width="19" height="19" viewBox="0 0 18 18" fill="#fff"><rect x="4" y="3" width="3.5" height="12" rx="1"/><rect x="10.5" y="3" width="3.5" height="12" rx="1"/></svg>
        </div>
        <svg width="21" height="21" viewBox="0 0 20 20" fill="#fff"><path d="M10.5 10L3 5v10l7.5-5zM18 10l-7.5-5v10L18 10z"/></svg>
        <svg width="18" height="18" viewBox="0 0 18 18" fill="rgba(255,255,255,0.82)"><path d="M3 4.5h12v1.6H3zm0 3.7h12v1.6H3zm0 3.7h9v1.6H3z"/></svg>
      </div>
    </div>'''


def vinyl_inner(device: str, loc: dict) -> str:
    p = loc["player"]
    np_hdr = f'''
    <div style="height:40px;padding:0 16px;display:flex;align-items:center;justify-content:space-between;flex-shrink:0;">
      <svg width="17" height="17" viewBox="0 0 18 18" fill="none" stroke="#fff" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M4.5 6.8L9 11.3l4.5-4.5"/></svg>
      <div style="display:flex;align-items:center;gap:14px;font-size:12px;">
        <span style="font-weight:800;color:#fff;">{p["tab_song"]}</span>
        <span style="width:1px;height:11px;background:rgba(255,255,255,0.28);"></span>
        <span style="font-weight:500;color:rgba(255,255,255,0.52);">{p["tab_lyrics"]}</span>
      </div>
      <svg width="17" height="17" viewBox="0 0 18 18" fill="none" stroke="#fff" stroke-width="1.6"><circle cx="9" cy="9" r="6.8"/><circle cx="9" cy="9" r="2.1"/></svg>
    </div>'''

    snippet1 = next(text for text, act in p["lyrics"] if act)
    snippet2 = p["lyrics"][3][0]

    if device == "ipad-13":
        lyric_divs = "".join(
            f'<div style="text-align:center;font-size:{"20px" if active else "14.5px"};font-weight:{"800" if active else "500"};color:{"#ffffff" if active else "rgba(255,255,255,0.46)"};padding:7px 0;">{line}</div>'
            for line, active in p["lyrics"]
        )
        return f'''
        {np_hdr}
        <div style="flex:1;padding:10px 28px 28px;display:grid;grid-template-columns:1fr 1fr;gap:26px;align-items:stretch;">
          <div style="display:flex;flex-direction:column;align-items:center;justify-content:space-between;padding:8px 12px;">
            <div style="flex:1;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:18px;">
              {vinyl_svg(290)}
              <div style="text-align:center;display:flex;flex-direction:column;gap:5px;">
                <div style="font-size:15px;font-weight:700;color:rgba(255,255,255,0.96);">{snippet1}</div>
                <div style="font-size:12.5px;color:rgba(255,255,255,0.58);">{snippet2}</div>
              </div>
            </div>
            {now_playing_controls_html(loc, wide=True)}
          </div>
          <div style="background:rgba(255,255,255,0.09);border-radius:24px;padding:22px 24px;display:flex;flex-direction:column;border:0.5px solid rgba(255,255,255,0.14);">
            <div style="font-size:20px;font-weight:800;color:#fff;margin-bottom:14px;">{p["synced_title"]}</div>
            <div style="flex:1;display:flex;flex-direction:column;justify-content:center;gap:6px;">
              {lyric_divs}
            </div>
          </div>
        </div>'''

    disc_sz = 194 if device == "iphone-duo" else 224
    gap = "10px" if device == "iphone-duo" else "16px"
    bot_pad = "16px" if device == "iphone-duo" else "24px"
    return f'''
    {np_hdr}
    <div style="flex:1;display:flex;flex-direction:column;align-items:center;justify-content:center;padding:4px 18px;gap:{gap};">
      {vinyl_svg(disc_sz)}
      <div style="text-align:center;display:flex;flex-direction:column;gap:4px;">
        <div style="font-size:11.5px;font-weight:700;color:rgba(255,255,255,0.96);">{snippet1}</div>
        <div style="font-size:9.8px;color:rgba(255,255,255,0.56);">{snippet2}</div>
      </div>
    </div>
    <div style="padding:4px 18px {bot_pad};">
      {now_playing_controls_html(loc, wide=False)}
    </div>'''


def classic_wheel_widget(wheel_px: int, compact: bool = False) -> str:
    center_px = int(wheel_px * 0.36)
    pad = int(wheel_px * 0.08)
    return f'''
    <div style="position:relative;width:{wheel_px}px;height:{wheel_px}px;border-radius:50%;background:linear-gradient(180deg,#ffffff 0%,#eff1f5 100%);border:1px solid rgba(0,0,0,0.08);box-shadow:0 8px 18px rgba(0,0,0,0.16);display:flex;align-items:center;justify-content:center;flex-shrink:0;">
      <div style="position:absolute;top:{pad}px;color:#5c616b;font-weight:700;font-size:{"9.5px" if compact else "11px"};letter-spacing:1.2px;">MENU</div>
      <div style="position:absolute;left:{pad}px;">
        <svg width="15" height="11" viewBox="0 0 18 14" fill="#5c616b"><rect x="1" y="2" width="2" height="10" rx="0.6"/><path d="M10 7l6-4.5v9L10 7zM4 7l6-4.5v9L4 7z"/></svg>
      </div>
      <div style="position:absolute;right:{pad}px;">
        <svg width="15" height="11" viewBox="0 0 18 14" fill="#5c616b"><rect x="15" y="2" width="2" height="10" rx="0.6"/><path d="M8 7L2 2.5v9L8 7zm6 0L8 2.5v9L14 7z"/></svg>
      </div>
      <div style="position:absolute;bottom:{pad}px;">
        <svg width="17" height="11" viewBox="0 0 20 14" fill="#5c616b"><path d="M2 2.5L9 7l-7 4.5z"/><rect x="11.5" y="2.5" width="2.4" height="9" rx="0.6"/><rect x="15.4" y="2.5" width="2.4" height="9" rx="0.6"/></svg>
      </div>
      <div style="width:{center_px}px;height:{center_px}px;border-radius:50%;background:linear-gradient(145deg,#d9dde3 0%,#c4c9d1 100%);border:1px solid rgba(255,255,255,0.65);box-shadow:0 2px 4px rgba(0,0,0,0.14);"></div>
    </div>'''


def classic_lcd_widget(loc: dict, compact: bool = False, wide_card: bool = False) -> str:
    p = loc["player"]
    art_px = "64px" if compact else ("82px" if wide_card else "74px")
    title_fs = "12.5px" if compact else ("15px" if wide_card else "13.5px")
    return f'''
    <div style="width:100%;flex:1;border-radius:14px;border:2px solid rgba(0,0,0,0.24);background:linear-gradient(180deg,#f0f7f2 0%,#e3efe8 100%);display:flex;flex-direction:column;overflow:hidden;color:#1a2126;box-shadow:inset 0 2px 6px rgba(0,0,0,0.06);">
      <div style="height:28px;padding:0 10px;background:rgba(0,0,0,0.055);border-bottom:1px solid rgba(0,0,0,0.08);display:flex;align-items:center;gap:6px;font-size:9.5px;font-weight:700;">
        <svg width="8" height="9" viewBox="0 0 10 12" fill="#008A82"><path d="M1 1l8 5-8 5z"/></svg>
        <span>{p["now_playing"]}</span>
        <span style="flex:1;"></span>
        <span style="font-size:8.5px;color:#62707a;font-variant-numeric:tabular-nums;">1/12</span>
        <svg width="11" height="11" viewBox="0 0 18 18" fill="none" stroke="#62707a" stroke-width="1.8" stroke-linecap="round"><path d="M13 3l2.5 2.5L13 8M3 9V7.5a2 2 0 0 1 2-2h10.5M5 15l-2.5-2.5L5 10M15 9v1.5a2 2 0 0 1-2 2H2.5"/></svg>
      </div>
      <div style="flex:1;padding:{"10px 12px" if compact else "14px"};display:flex;flex-direction:column;justify-content:space-between;">
        <div style="display:flex;align-items:center;gap:12px;">
          <div style="width:{art_px};height:{art_px};border-radius:9px;flex-shrink:0;background:linear-gradient(135deg,#008A82 0%,#1d4ed8 55%,#f59e0b 100%);box-shadow:0 4px 10px rgba(0,0,0,0.16);display:flex;align-items:center;justify-content:center;">
            <svg width="26" height="26" viewBox="0 0 24 24" fill="rgba(255,255,255,0.9)"><path d="M9 18V5l12-2v13M9 18a3 3 0 1 1-6 0 3 3 0 0 1 6 0zm12-2a3 3 0 1 1-6 0 3 3 0 0 1 6 0z"/></svg>
          </div>
          <div style="flex:1;min-width:0;">
            <div style="font-size:{title_fs};font-weight:800;color:#141a1e;line-height:1.25;">{p["classic_title"]}</div>
            <div style="font-size:{"10px" if compact else "11px"};color:#526069;margin-top:3px;">{p["classic_artist"]}</div>
            <div style="font-size:{"8.5px" if compact else "9.5px"};color:#6c7b85;margin-top:2px;">{p["classic_source"]}</div>
          </div>
        </div>
        <div style="text-align:center;font-size:{"9.8px" if compact else "10.5px"};font-weight:600;color:#008A82;">{p["classic_lyric"]}</div>
        <div>
          <div style="height:6px;border-radius:3px;background:rgba(0,0,0,0.12);overflow:hidden;">
            <div style="width:42%;height:100%;background:#008A82;border-radius:3px;"></div>
          </div>
          <div style="display:flex;justify-content:space-between;margin-top:4px;font-size:8.5px;color:#5c6b75;font-variant-numeric:tabular-nums;">
            <span>00:48</span><span>03:45</span>
          </div>
        </div>
      </div>
    </div>'''


def classic_inner(device: str, loc: dict) -> str:
    p = loc["player"]
    if device == "ipad-13":
        grads = ["#008A82,#1d4ed8", "#0f766e,#2563eb", "#f59e0b,#db2777", "#3b82f6,#0d9488", "#d97757,#63438f", "#059669,#0284c7", "#7c3aed,#2563eb"]
        queue_html = "".join(
            f'''<div style="display:flex;align-items:center;gap:12px;padding:11px 12px;border-radius:12px;background:{"rgba(255,255,255,0.16)" if idx == 0 else "rgba(255,255,255,0.06)"};">
                  <div style="width:40px;height:40px;border-radius:8px;background:linear-gradient(135deg,{grads[idx]});display:flex;align-items:center;justify-content:center;color:#fff;font-weight:800;font-size:14px;">{title[0]}</div>
                  <div style="flex:1;min-width:0;">
                    <div style="font-size:14px;font-weight:700;color:#fff;">{title}</div>
                    <div style="font-size:11.5px;color:rgba(255,255,255,0.72);margin-top:2px;">{artist}</div>
                  </div>
                  {"<svg width='16' height='16' viewBox='0 0 18 18'><path d='M3 7h3l4-3.5v11L6 11H3zM12.5 5.5a5 5 0 0 1 0 7M14.5 3.5a8 8 0 0 1 0 11' stroke='#fff' stroke-width='1.5' fill='none' stroke-linecap='round'/></svg>" if idx == 0 else ""}
                </div>'''
            for idx, (title, artist) in enumerate(p["queue"])
        )
        return f'''
        <div style="height:40px;padding:0 16px;display:flex;align-items:center;justify-content:space-between;flex-shrink:0;">
          <svg width="17" height="17" viewBox="0 0 18 18" fill="none" stroke="#fff" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M4.5 6.8L9 11.3l4.5-4.5"/></svg>
          <div style="display:flex;align-items:center;gap:14px;font-size:12px;">
            <span style="font-weight:800;color:#fff;">{p["tab_song"]}</span>
            <span style="width:1px;height:11px;background:rgba(255,255,255,0.28);"></span>
            <span style="font-weight:500;color:rgba(255,255,255,0.52);">{p["tab_lyrics"]}</span>
          </div>
          <svg width="17" height="17" viewBox="0 0 18 18" fill="none" stroke="#fff" stroke-width="1.6"><circle cx="9" cy="9" r="6.8"/><circle cx="9" cy="9" r="2.1"/></svg>
        </div>
        <div style="flex:1;padding:10px 28px 28px;display:grid;grid-template-columns:1fr 1fr;gap:26px;align-items:stretch;">
          <div style="display:flex;align-items:center;justify-content:center;">
            <div style="width:360px;height:600px;border-radius:34px;padding:18px;background:linear-gradient(145deg,#e6e8ed 0%,#c7ccd4 100%);border:1.5px solid rgba(255,255,255,0.68);box-shadow:0 22px 44px rgba(0,0,0,0.34);display:flex;flex-direction:column;align-items:center;justify-content:space-between;gap:18px;">
              {classic_lcd_widget(loc, compact=False, wide_card=True)}
              {classic_wheel_widget(220, compact=False)}
            </div>
          </div>
          <div style="background:rgba(255,255,255,0.09);border-radius:24px;padding:22px 24px;display:flex;flex-direction:column;border:0.5px solid rgba(255,255,255,0.14);">
            <div style="font-size:20px;font-weight:800;color:#fff;margin-bottom:14px;">{p["queue_title"]}</div>
            <div style="flex:1;display:flex;flex-direction:column;gap:9px;justify-content:flex-start;">
              {queue_html}
            </div>
          </div>
        </div>'''

    compact = device == "iphone-duo"
    wheel_px = 176 if compact else 208
    body_pad = "2px 14px 16px" if compact else "4px 16px 24px"
    gap = "12px" if compact else "18px"
    return f'''
    <div style="height:38px;padding:0 14px;display:flex;align-items:center;justify-content:space-between;flex-shrink:0;">
      <svg width="16" height="16" viewBox="0 0 18 18" fill="none" stroke="#38404a" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M4.5 6.8L9 11.3l4.5-4.5"/></svg>
      <svg width="16" height="16" viewBox="0 0 18 18" fill="none" stroke="#38404a" stroke-width="1.6"><circle cx="9" cy="9" r="6.8"/><circle cx="9" cy="9" r="2.1"/></svg>
    </div>
    <div style="flex:1;padding:{body_pad};display:flex;flex-direction:column;align-items:center;justify-content:space-between;gap:{gap};">
      {classic_lcd_widget(loc, compact=compact)}
      {classic_wheel_widget(wheel_px, compact=compact)}
    </div>'''


def search_inner(device: str, loc: dict) -> str:
    s = loc["search"]
    compact = device == "iphone-duo"
    wide = device == "ipad-13"
    rows = s["rows"][:4] if compact else s["rows"]
    row_markup = ""
    for title, artist, meta, active_title, dl, done, short, grad, glyph in rows:
        short_pill = f'<span style="font-size:8px;font-weight:700;color:#008A82;padding:1px 6px;border-radius:99px;background:rgba(0,138,130,0.12);margin-left:5px;white-space:nowrap;">{s["short_badge"]}</span>' if short else ''
        play_btn = (
            f'<div style="width:{"36px" if wide else "30px"};height:{"36px" if wide else "30px"};border-radius:50%;background:rgba(0,138,130,0.12);display:flex;align-items:center;justify-content:center;">'
            + ('<svg width="11" height="11" viewBox="0 0 16 16" fill="#008A82"><rect x="3.5" y="2.5" width="3" height="11" rx="1"/><rect x="9.5" y="2.5" width="3" height="11" rx="1"/></svg>' if active_title else '<svg width="11" height="11" viewBox="0 0 16 16" fill="#008A82"><path d="M4 2.5l9 5.5-9 5.5z"/></svg>')
            + '</div>'
        )
        dl_btn = ""
        if dl:
            inner_ico = (
                '<svg width="12" height="12" viewBox="0 0 16 16" fill="none" stroke="#16a34a" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M3 8.5l3.2 3.2L13 4.8"/></svg>'
                if done else
                '<svg width="12" height="12" viewBox="0 0 16 16" fill="none" stroke="#141923" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M8 3v8M4.5 7.8L8 11.3l3.5-3.5M3 13.5h10"/></svg>'
            )
            dl_btn = f'<div style="width:{"32px" if wide else "27px"};height:{"32px" if wide else "27px"};border-radius:50%;border:2px solid rgba(0,138,130,0.22);display:flex;align-items:center;justify-content:center;">{inner_ico}</div>'
        cover_px = "48px" if wide else ("36px" if compact else "40px")
        row_markup += f'''
        <div style="display:flex;align-items:center;gap:10px;padding:{"10px 14px" if wide else "7.5px 10px"};border-radius:{"14px" if wide else "12px"};background:rgba(255,255,255,0.82);border:0.5px solid rgba(255,255,255,0.95);">
          <div style="width:{cover_px};height:{cover_px};border-radius:9px;flex-shrink:0;background:linear-gradient(135deg,{grad});display:flex;align-items:center;justify-content:center;color:#fff;font-weight:800;font-size:{"16px" if wide else "13px"};">{glyph}</div>
          <div style="flex:1;min-width:0;">
            <div style="display:flex;align-items:center;">
              <span style="font-size:{"14px" if wide else "11px"};font-weight:{"700" if active_title else "600"};color:{"#008A82" if active_title else "#141820"};white-space:nowrap;overflow:hidden;text-overflow:ellipsis;">{title}</span>
              {short_pill}
            </div>
            <div style="font-size:{"11.5px" if wide else "9px"};color:#5c6676;margin-top:2px;">{artist}</div>
            <div style="font-size:{"10.5px" if wide else "8px"};color:#7a8596;margin-top:1px;">{meta}</div>
          </div>
          <div style="display:flex;align-items:center;gap:7px;">{play_btn}{dl_btn}</div>
        </div>'''

    chip_html = "".join(
        f'<span style="font-size:{"11.5px" if wide else "8.8px"};font-weight:700;padding:{"5px 12px" if wide else "4px 9px"};border-radius:99px;background:{"#008A82" if idx==1 else "rgba(255,255,255,0.82)"};color:{"#fff" if idx==1 else "#1a202c"};white-space:nowrap;">{c}</span>'
        for idx, c in enumerate(s["chips"])
    )
    return f'''
    <div style="flex:1;padding:{"14px 28px" if wide else "8px 14px"};display:flex;flex-direction:column;gap:{"12px" if wide else "8px"};overflow:hidden;">
      <div style="text-align:center;font-size:{"17px" if wide else "13px"};font-weight:700;color:#11151c;">{s["nav_title"]}</div>
      <div style="display:flex;align-items:center;gap:8px;">
        <div style="flex:1;display:flex;align-items:center;gap:7px;padding:{"9px 14px" if wide else "7px 11px"};border-radius:99px;background:rgba(255,255,255,0.88);border:0.5px solid rgba(255,255,255,0.96);">
          <svg width="13" height="13" viewBox="0 0 16 16" fill="none" stroke="#64748b" stroke-width="1.8"><circle cx="7" cy="7" r="4.8"/><path d="M10.7 10.7L14 14"/></svg>
          <span style="font-size:{"13px" if wide else "10.5px"};color:#11151c;font-weight:500;">{s["query"]}</span>
          <span style="flex:1;"></span>
          <span style="width:14px;height:14px;border-radius:50%;background:rgba(100,116,139,0.35);color:#fff;font-size:9px;display:flex;align-items:center;justify-content:center;">×</span>
        </div>
        <div style="padding:{"9px 18px" if wide else "7px 13px"};border-radius:99px;background:#008A82;color:#fff;font-size:{"13px" if wide else "10.5px"};font-weight:700;white-space:nowrap;">{s["button"]}</div>
      </div>
      <div style="display:flex;align-items:center;gap:7px;overflow:hidden;">{chip_html}</div>
      <div style="display:flex;flex-direction:column;gap:{"9px" if wide else "6.5px"};flex:1;">
        {row_markup}
      </div>
    </div>'''


def mini_dock_html(loc: dict, wide: bool = False, in_duo: bool = False) -> str:
    h = loc["home"]
    margin = "0 26px 14px" if wide else ("0 12px 10px" if in_duo else "0 12px 6px")
    height = "58px" if wide else "44px"
    return f'''
    <div style="position:relative;margin:{margin};height:{height};border-radius:99px;background:rgba(255,255,255,0.92);border:0.5px solid rgba(255,255,255,0.98);box-shadow:0 8px 20px rgba(15,23,42,0.11);padding:{"0 16px 0 8px" if wide else "0 12px 0 6px"};display:flex;align-items:center;gap:10px;flex-shrink:0;overflow:hidden;">
      <div style="position:absolute;top:0;left:0;width:48%;height:2.2px;background:#008A82;"></div>
      <div style="width:{"42px" if wide else "32px"};height:{"42px" if wide else "32px"};border-radius:50%;background:linear-gradient(135deg,#008A82,#3154b8);flex-shrink:0;"></div>
      <div style="flex:1;min-width:0;">
        <div style="font-size:{"13px" if wide else "10px"};font-weight:700;color:#11151c;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;">{h["mini_title"]}</div>
        <div style="font-size:{"10.5px" if wide else "8px"};color:#5f6978;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;">{h["mini_sub"]}</div>
      </div>
      <svg width="{"17" if wide else "14"}" height="{"17" if wide else "14"}" viewBox="0 0 16 16" fill="#141923"><rect x="3.5" y="2.5" width="3" height="11" rx="1"/><rect x="9.5" y="2.5" width="3" height="11" rx="1"/></svg>
      <svg width="{"17" if wide else "14"}" height="{"17" if wide else "14"}" viewBox="0 0 16 16" fill="#141923" style="margin-left:4px;"><path d="M2 4h12v1.6H2zm0 3.6h12v1.6H2zm0 3.6h9v1.6H2z"/></svg>
    </div>'''


def build_device_shell(device: str, poster_spec: dict, inner_html: str, loc: dict) -> str:
    slug = poster_spec["slug"]
    is_now_playing = "vinyl" in slug or "classic" in slug
    is_classic = "classic" in slug
    if is_classic and device != "ipad-13":
        screen_bg = "linear-gradient(145deg, #e6e8ed 0%, #c7ccd4 100%)"
        status_color = "#38404a"
        indicator_bg = "rgba(56,64,74,0.34)"
    elif is_now_playing:
        screen_bg = "linear-gradient(150deg, #1d4e89 0%, #11325c 52%, #0a1f3d 100%)"
        status_color = "#ffffff"
        indicator_bg = "rgba(255,255,255,0.38)"
    else:
        screen_bg = "linear-gradient(150deg, #DCE9FF 0%, #EDE8FC 50%, #F6EFF9 100%)"
        status_color = "#0f172a"
        indicator_bg = "rgba(15,23,42,0.30)"

    active_tab = poster_spec["active_tab"]
    show_tabs = not is_now_playing
    tabs = loc["tabs"]

    if device == "iphone-medium":
        tab_bar = ""
        if show_tabs:
            items = "".join(
                f'''<div style="display:flex;flex-direction:column;align-items:center;justify-content:center;gap:2px;font-size:7.6px;font-weight:{"700" if i==active_tab else "600"};color:{"#008A82" if i==active_tab else "#334155"};padding:4px 0;border-radius:99px;background:{"rgba(0,138,130,0.12)" if i==active_tab else "transparent"};">{tab_icon_svg(i, "#008A82" if i==active_tab else "#334155")}<span>{lbl}</span></div>'''
                for i, lbl in enumerate(tabs)
            )
            tab_bar = f'''
            {mini_dock_html(loc, False)}
            <div style="margin:0 12px 12px;height:44px;padding:3px;border-radius:99px;background:rgba(255,255,255,0.74);backdrop-filter:blur(12px);border:0.5px solid rgba(255,255,255,0.92);box-shadow:0 8px 22px rgba(15,23,42,0.12);display:grid;grid-template-columns:repeat(4,1fr);align-items:center;flex-shrink:0;">
              {items}
            </div>'''
        return f'''
        <div style="width:318px;height:680px;border-radius:46px;padding:8px;background:linear-gradient(145deg,#3c424d 0%,#1d2026 48%,#2e333c 100%);box-shadow:0 24px 54px rgba(0,0,0,0.62),0 0 0 1px rgba(255,255,255,0.16) inset;">
          <div style="position:relative;width:100%;height:100%;border-radius:38px;overflow:hidden;display:flex;flex-direction:column;background:{screen_bg};color:{status_color};">
            <div style="position:absolute;top:9px;left:50%;transform:translateX(-50%);width:82px;height:22px;border-radius:11px;background:#060709;z-index:30;"></div>
            <div style="height:34px;padding:9px 20px 0;display:flex;align-items:center;justify-content:space-between;font-size:10.5px;font-weight:700;color:{status_color};flex-shrink:0;">
              <span>9:41</span>{status_icons_svg(status_color)}
            </div>
            {inner_html}
            {tab_bar}
            <div style="position:absolute;bottom:4px;left:50%;transform:translateX(-50%);width:96px;height:3.2px;border-radius:2px;background:{indicator_bg};"></div>
          </div>
        </div>'''

    if device == "iphone-duo":
        # Full edge-to-edge screen background (ZERO black bar on the right); translucent floating Duo rail!
        rail_pill_bg = "rgba(15,23,42,0.58)" if (is_now_playing and not is_classic) else "rgba(255,255,255,0.72)"
        rail_border = "rgba(255,255,255,0.18)" if (is_now_playing and not is_classic) else "rgba(255,255,255,0.92)"
        rail_txt = "#ffffff" if (is_now_playing and not is_classic) else "#0f172a"
        rail_tabs = "".join(
            f'<div style="width:28px;height:28px;border-radius:50%;display:flex;align-items:center;justify-content:center;background:{"rgba(0,138,130,0.18)" if i==active_tab else "transparent"};">{tab_icon_svg(i, "#008A82" if i==active_tab else ("#cbd5e1" if (is_now_playing and not is_classic) else "#334155"))}</div>'
            for i in range(4)
        )
        right_rail = f'''
        <div style="width:52px;height:100%;display:flex;flex-direction:column;align-items:center;justify-content:space-between;padding:16px 6px 14px 2px;flex-shrink:0;">
          <div style="display:flex;flex-direction:column;align-items:center;gap:9px;">
            <span style="font-size:10px;font-weight:700;color:{rail_txt};">9:41</span>
            <svg width="24" height="24" viewBox="0 0 28 28">
              <circle cx="14" cy="14" r="10.5" fill="none" stroke="{"rgba(255,255,255,0.22)" if (is_now_playing and not is_classic) else "rgba(15,23,42,0.14)"}" stroke-width="2.4"/>
              <path d="M5.5 14a8.5 8.5 0 0 1 17 0" fill="none" stroke="#16a34a" stroke-width="2.4" stroke-linecap="round"/>
              <circle cx="14" cy="15" r="2.2" fill="{rail_txt}"/>
            </svg>
            <div style="width:24px;height:24px;border-radius:50%;background:#008A82;color:#fff;display:flex;align-items:center;justify-content:center;font-size:15px;font-weight:700;box-shadow:0 4px 10px rgba(0,138,130,0.35);">+</div>
          </div>
          <div style="display:flex;flex-direction:column;align-items:center;gap:5px;padding:7px 4px;border-radius:22px;background:{rail_pill_bg};border:0.5px solid {rail_border};box-shadow:0 6px 16px rgba(0,0,0,0.12);">
            {rail_tabs}
          </div>
        </div>'''
        return f'''
        <div style="width:396px;height:512px;border-radius:30px;padding:7px;background:linear-gradient(145deg,#3c424d 0%,#1a1d22 48%,#2b3038 100%);box-shadow:0 22px 48px rgba(0,0,0,0.62),0 0 0 1px rgba(255,255,255,0.16) inset;">
          <div style="position:relative;width:100%;height:100%;border-radius:24px;overflow:hidden;display:flex;flex-direction:row;background:{screen_bg};color:{status_color};">
            <div style="position:relative;flex:1;height:100%;display:flex;flex-direction:column;overflow:hidden;">
              <div style="height:8px;flex-shrink:0;"></div>
              {inner_html}
              {mini_dock_html(loc, False, in_duo=True) if show_tabs else ""}
            </div>
            {right_rail}
          </div>
        </div>'''

    pill_tabs = ""
    if show_tabs:
        tab_items = "".join(
            f'<span style="padding:6px 16px;border-radius:99px;font-size:13.5px;font-weight:700;background:{"#008A82" if i==active_tab else "transparent"};color:{"#fff" if i==active_tab else "#334155"};">{lbl}</span>'
            for i, lbl in enumerate(tabs)
        )
        pill_tabs = f'''
        <div style="padding:2px 26px 6px;display:flex;justify-content:center;flex-shrink:0;">
          <div style="display:inline-flex;align-items:center;gap:4px;padding:4px;border-radius:99px;background:rgba(255,255,255,0.82);border:0.5px solid rgba(255,255,255,0.95);box-shadow:0 4px 12px rgba(0,0,0,0.06);">
            {tab_items}
          </div>
        </div>'''

    return f'''
    <div style="width:868px;height:1098px;border-radius:36px;padding:12px;background:linear-gradient(145deg,#3e4450 0%,#1a1d24 48%,#2b303a 100%);box-shadow:0 32px 72px rgba(0,0,0,0.65),0 0 0 1.5px rgba(255,255,255,0.18) inset;">
      <div style="position:relative;width:100%;height:100%;border-radius:26px;overflow:hidden;display:flex;flex-direction:column;background:{screen_bg};color:{status_color};">
        <div style="height:34px;padding:10px 24px 0;display:flex;align-items:center;justify-content:space-between;font-size:12px;font-weight:700;color:{status_color};flex-shrink:0;">
          <span>9:41  {loc["status_brand"]}</span>{status_icons_svg(status_color)}
        </div>
        {pill_tabs}
        {inner_html}
        {mini_dock_html(loc, True) if show_tabs else ""}
        <div style="position:absolute;bottom:7px;left:50%;transform:translateX(-50%);width:220px;height:4.5px;border-radius:3px;background:{indicator_bg};"></div>
      </div>
    </div>'''


def poster_html(locale_code: str, device: str, poster_idx: int, piano_uri: str) -> str:
    spec = DEVICES[device]
    vw, vh = spec["vw"], spec["vh"]
    ps = POSTER_SPECS[poster_idx]
    loc = LOCALE_CONTENT[locale_code]
    copy_info = loc["posters"][poster_idx]
    slug = ps["slug"]

    if "discovery" in slug:
        inner = discovery_inner(device, loc, piano_uri)
    elif "vinyl" in slug:
        inner = vinyl_inner(device, loc)
    elif "classic" in slug:
        inner = classic_inner(device, loc)
    else:
        inner = search_inner(device, loc)

    bezel = build_device_shell(device, ps, inner, loc)
    is_latin = locale_code in ("en-US", "fr-FR")

    if device == "ipad-13":
        copy_pad = "44px 42px 24px"
        eyebrow_fs = "21px"
        head_fs = "50px" if is_latin else "58px"
        sub_fs = "22px" if is_latin else "24px"
        arc_size = 900
    elif device == "iphone-duo":
        copy_pad = "18px 18px 8px"
        eyebrow_fs = "10.5px"
        head_fs = "23px" if is_latin else "27px"
        sub_fs = "10.5px" if is_latin else "11.5px"
        arc_size = 480
    else:
        copy_pad = "24px 16px 12px"
        eyebrow_fs = "10.5px"
        head_fs = "22.5px" if is_latin else "27px"
        sub_fs = "10.5px" if is_latin else "11.5px"
        arc_size = 500

    return f"""<!DOCTYPE html><html><head><meta charset="utf-8"><style>
    * {{ box-sizing: border-box; margin: 0; padding: 0; }}
    html, body {{
      width: {vw}px; height: {vh}px; overflow: hidden;
      font-family: {loc["font_stack"]};
      -webkit-font-smoothing: antialiased;
    }}
    .canvas {{
      position: relative; width: {vw}px; height: {vh}px;
      display: flex; flex-direction: column; align-items: center; overflow: hidden;
    }}
    .glow-arc {{ position: absolute; border-radius: 50%; pointer-events: none; }}
    .glow-arc.a1 {{ width: {arc_size}px; height: {arc_size}px; top: 18%; right: -{int(arc_size*0.36)}px; }}
    .glow-arc.a2 {{ width: {int(arc_size*0.88)}px; height: {int(arc_size*0.88)}px; bottom: -{int(arc_size*0.24)}px; left: -{int(arc_size*0.32)}px; }}
    {canvas_backdrop_css(ps["theme"])}
    .copy {{ position: relative; z-index: 5; width: 100%; padding: {copy_pad}; text-align: center; }}
    .eyebrow {{ display:inline-flex;align-items:center;gap:10px;font-size:{eyebrow_fs};font-weight:600;letter-spacing:2.2px;color:rgba(255,255,255,0.74);margin-bottom:7px; }}
    .eyebrow .line {{ display:inline-block;width:{"30px" if device=="ipad-13" else "16px"};height:1px;background:rgba(255,255,255,0.35); }}
    .headline {{ font-size:{head_fs};font-weight:800;letter-spacing:-0.4px;line-height:1.18;color:#fff;text-shadow:0 4px 16px rgba(0,0,0,0.35);margin-bottom:7px; }}
    .subhead {{ font-size:{sub_fs};font-weight:500;color:rgba(255,255,255,0.80);letter-spacing:0.3px; }}
    .device-wrap {{ position:relative;z-index:5;flex:1;width:100%;display:flex;justify-content:center;align-items:flex-start;padding-top:{"6px" if device!="iphone-duo" else "4px"}; }}
    </style></head><body>
    <div class="canvas">
      <div class="glow-arc a1"></div>
      <div class="glow-arc a2"></div>
      <div class="copy">
        <div class="eyebrow"><span class="line"></span>{loc["brand"]}<span class="line"></span></div>
        <div class="headline">{copy_info["title"]}</div>
        <div class="subhead">{copy_info["subhead"]}</div>
      </div>
      <div class="device-wrap">{bezel}</div>
    </div>
    </body></html>"""


def verify_png_rgb(path: Path, expected_w: int, expected_h: int):
    data = path.read_bytes()
    assert data[:8] == b"\x89PNG\r\n\x1a\n"
    w, h, depth, color = struct.unpack(">IIBB", data[16:26])
    assert (w, h, depth, color) == (expected_w, expected_h, 8, 2), f"{path.name}: {(w, h, depth, color)}"
    assert b"tRNS" not in data, f"{path.name} contains tRNS"


def render_one(locale_code: str, device: str, poster_idx: int, piano_uri: str, work_dir: Path) -> Path:
    spec = DEVICES[device]
    slug = POSTER_SPECS[poster_idx]["slug"]
    out_dir = OUT_DIR / locale_code / device
    out_dir.mkdir(parents=True, exist_ok=True)
    html_file = work_dir / f"{locale_code}-{device}-{slug}.html"
    raw_png = work_dir / f"{locale_code}-{device}-{slug}.raw.png"
    out_png = out_dir / f"{slug}.png"

    html_file.write_text(poster_html(locale_code, device, poster_idx, piano_uri), encoding="utf-8")
    with tempfile.TemporaryDirectory() as profile_dir:
        subprocess.run(
            [
                EDGE,
                "--headless=new",
                "--disable-gpu",
                "--hide-scrollbars",
                f"--user-data-dir={profile_dir}",
                f"--window-size={spec['vw']},{spec['vh']}",
                f"--force-device-scale-factor={spec['scale']}",
                f"--screenshot={raw_png}",
                html_file.as_uri(),
            ],
            check=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )

    im = Image.open(raw_png).convert("RGB")
    if im.size != (spec["width"], spec["height"]):
        im = im.resize((spec["width"], spec["height"]), Image.Resampling.LANCZOS)
    im.save(out_png, format="PNG", optimize=True, compress_level=9)
    verify_png_rgb(out_png, spec["width"], spec["height"])
    return out_png


def main():
    piano_uri = hero_piano_uri()
    manifest = []
    with tempfile.TemporaryDirectory() as tmp:
        work_dir = Path(tmp)
        for locale_code in ("zh-Hans", "zh-Hant", "en-US", "fr-FR"):
            loc = LOCALE_CONTENT[locale_code]
            locale_rows = []
            for device in ("iphone-medium", "iphone-duo", "ipad-13"):
                spec = DEVICES[device]
                device_paths = []
                for idx, ps in enumerate(POSTER_SPECS):
                    out_png = render_one(locale_code, device, idx, piano_uri, work_dir)
                    device_paths.append(out_png)
                    sha = hashlib.sha256(out_png.read_bytes()).hexdigest()
                    manifest.append({
                        "locale": locale_code,
                        "file": f"{locale_code}/{device}/{ps['slug']}.png",
                        "width": spec["width"],
                        "height": spec["height"],
                        "title": loc["posters"][idx]["title"],
                        "sha256": sha,
                    })
                    print(f"Rendered {locale_code}/{device}/{ps['slug']}.png ({spec['width']}x{spec['height']})")
                locale_rows.append(device_paths)

            if ARTIFACT_DIR.exists():
                pad = 16
                target_h = 560
                row_imgs = []
                for paths in locale_rows:
                    thumbs = []
                    for p in paths:
                        im = Image.open(p).convert("RGB")
                        thumbs.append(im.resize((int(im.width * (target_h / im.height)), target_h), Image.Resampling.LANCZOS))
                    rw = sum(t.width for t in thumbs) + pad * 5
                    row_img = Image.new("RGB", (rw, target_h + pad * 2), (10, 14, 20))
                    x = pad
                    for t in thumbs:
                        row_img.paste(t, (x, pad))
                        x += t.width + pad
                    row_imgs.append(row_img)
                max_w = max(r.width for r in row_imgs)
                total_h = sum(r.height for r in row_imgs)
                grid = Image.new("RGB", (max_w, total_h), (10, 14, 20))
                y = 0
                for r in row_imgs:
                    grid.paste(r, ((max_w - r.width) // 2, y))
                    y += r.height
                grid.save(ARTIFACT_DIR / f"preview-{locale_code}.png", format="PNG")

    (OUT_DIR / "文件验收清单.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Wrote manifest with {len(manifest)} entries.")


if __name__ == "__main__":
    main()
