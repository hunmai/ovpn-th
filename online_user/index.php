<?php
// --- Proxy function ---
function fetchOnlineCount($url) {
    $allowed_domains = [];
    for ($i = 1; $i <= 35; $i++) {
        $allowed_domains[] = sprintf('nn%02d.pukangvpn.xyz', $i);
    }
    
    $domain = parse_url($url, PHP_URL_HOST);
    if (in_array($domain, $allowed_domains)) {
        $context = stream_context_create(['http' => ['timeout' => 5, 'ignore_errors' => true]]);
        $response = @file_get_contents($url, false, $context);
        if ($response !== false && is_numeric(trim($response))) {
            return intval(trim($response));
        }
    }
    return false;
}

$servers = [];
for ($i = 1; $i <= 35; $i++) {
    $num = sprintf('%02d', $i);
    $servers["🇹🇭 THAILAND-$num"] = [
        "http://nn{$num}.pukangvpn.xyz:82/server/online", 
        "http://nn{$num}.pukangvpn.xyz:82/udpserver/online"
    ];
}

$maxCapacity = 250;
$serverStatuses = [];
$totalOnline = 0;

foreach ($servers as $name => $urls) {
    $online = 0;
    $success = false;
    foreach ($urls as $url) {
        $count = fetchOnlineCount($url);
        if ($count !== false) {
            $online += $count;
            $success = true;
        }
    }
    $serverStatuses[$name] = ['online' => $online, 'success' => $success];
    if ($success) $totalOnline += $online;
}

function getStatusClass($online) {
    if ($online > 200) return 'highload';
    if ($online > 150) return 'busy';
    return 'normal';
}
function getStatusText($online) {
    if ($online > 200) return 'HIGH LOAD';
    if ($online > 150) return 'BUSY';
    return 'ONLINE';
}
function getDotClass($online) {
    if ($online > 200) return 'dot-red';
    if ($online > 150) return 'dot-yellow';
    return 'dot-green';
}
function getTotalDotClass($total) {
    $totalServers = count($GLOBALS['servers']);
    $avg = $total / $totalServers;
    if ($avg > 200) return 'dot-red';
    if ($avg > 150) return 'dot-yellow';
    return 'dot-green';
}
function getPercentage($online, $max) {
    if ($max <= 0) return 0;
    return min(100, round(($online / $max) * 100));
}
function getBarColorClass($percent) {
    if ($percent >= 95) return 'bar-red';
    if ($percent >= 50) return 'bar-yellow';
    return 'bar-green';
}

header("Content-Security-Policy: frame-ancestors *;");
?>
<!DOCTYPE html>
<html lang="th" class="dark">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Cyber Node // Server Status</title>
    <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bootstrap-icons@1.11.3/font/bootstrap-icons.min.css">
    <link href="https://fonts.googleapis.com/css2?family=Outfit:wght@400;500;600;700;800&display=swap" rel="stylesheet">
    <style>
        :root {
            --bg: #030712;
            --surface: rgba(17, 24, 39, 0.7);
            --surface-solid: #111827;
            --border: rgba(255, 255, 255, 0.08);
            --text-main: #f9fafb;
            --text-muted: #9ca3af;
            --primary: #3b82f6;
            --green: #10b981;
            --yellow: #f59e0b;
            --red: #ef4444;
            --glow-green: rgba(16, 185, 129, 0.4);
            --glow-red: rgba(239, 68, 68, 0.4);
        }

        .light {
            --bg: #f8fafc;
            --surface: rgba(255, 255, 255, 0.85);
            --surface-solid: #ffffff;
            --border: rgba(0, 0, 0, 0.08);
            --text-main: #0f172a;
            --text-muted: #64748b;
        }

        * { margin: 0; padding: 0; box-sizing: border-box; font-family: 'Outfit', sans-serif; }
        
        body {
            background-color: var(--bg);
            color: var(--text-main);
            min-height: 100vh;
            background-image: 
                radial-gradient(at 0% 0%, rgba(59, 130, 246, 0.1) 0px, transparent 50%),
                radial-gradient(at 100% 100%, rgba(16, 185, 129, 0.08) 0px, transparent 50%);
            background-attachment: fixed;
            transition: background 0.3s ease, color 0.3s ease;
            padding-bottom: 3rem;
        }

        .navbar {
            position: sticky;
            top: 0;
            backdrop-filter: blur(16px);
            background: var(--surface);
            border-bottom: 1px solid var(--border);
            padding: 1rem 2rem;
            z-index: 100;
        }

        .nav-container {
            max-width: 1300px;
            margin: 0 auto;
            display: flex;
            justify-content: space-between;
            align-items: center;
        }

        .brand {
            display: flex;
            align-items: center;
            gap: 0.75rem;
            font-weight: 800;
            font-size: 1.25rem;
            letter-spacing: 0.5px;
            color: var(--text-main);
            text-decoration: none;
        }

        .brand img { width: 32px; height: 32px; filter: drop-shadow(0 0 8px rgba(59,130,246,0.5)); }

        .nav-actions {
            display: flex;
            align-items: center;
            gap: 1rem;
        }

        .theme-toggle {
            background: var(--surface-solid);
            border: 1px solid var(--border);
            color: var(--text-main);
            width: 40px;
            height: 40px;
            border-radius: 12px;
            cursor: pointer;
            display: flex;
            align-items: center;
            justify-content: center;
            transition: all 0.2s;
        }
        .theme-toggle:hover { border-color: var(--primary); transform: scale(1.05); }

        .main-container {
            max-width: 1300px;
            margin: 2rem auto 0;
            padding: 0 1.5rem;
        }

        .dashboard-header {
            display: flex;
            justify-content: space-between;
            align-items: center;
            margin-bottom: 2rem;
            flex-wrap: wrap;
            gap: 1rem;
        }

        .header-title h1 {
            font-size: 1.75rem;
            font-weight: 700;
            display: flex;
            align-items: center;
            gap: 0.5rem;
        }
        .header-title p { color: var(--text-muted); font-size: 0.9rem; }

        .total-badge {
            background: var(--surface);
            backdrop-filter: blur(10px);
            border: 1px solid var(--border);
            padding: 0.75rem 1.25rem;
            border-radius: 16px;
            display: flex;
            align-items: center;
            gap: 0.75rem;
            box-shadow: 0 10px 25px -5px rgba(0,0,0,0.2);
        }

        .server-grid {
            display: grid;
            grid-template-columns: repeat(auto-fill, minmax(280px, 1fr));
            gap: 1.25rem;
        }

        .server-card {
            background: var(--surface);
            backdrop-filter: blur(12px);
            border: 1px solid var(--border);
            border-radius: 20px;
            padding: 1.25rem;
            display: flex;
            flex-direction: column;
            gap: 1rem;
            transition: all 0.3s cubic-bezier(0.4, 0, 0.2, 1);
            position: relative;
            overflow: hidden;
        }

        .server-card:hover {
            transform: translateY(-5px);
            border-color: rgba(59, 130, 246, 0.4);
            box-shadow: 0 20px 30px -10px rgba(0, 0, 0, 0.3);
        }

        .card-top {
            display: flex;
            justify-content: space-between;
            align-items: center;
        }

        .server-name {
            font-weight: 700;
            font-size: 1.1rem;
            display: flex;
            align-items: center;
            gap: 0.5rem;
        }

        .status-badge {
            font-size: 0.7rem;
            font-weight: 700;
            padding: 0.25rem 0.6rem;
            border-radius: 20px;
            letter-spacing: 0.5px;
            text-transform: uppercase;
        }
        .status-badge.normal { background: rgba(16, 185, 129, 0.15); color: var(--green); border: 1px solid rgba(16, 185, 129, 0.3); }
        .status-badge.busy { background: rgba(245, 158, 11, 0.15); color: var(--yellow); border: 1px solid rgba(245, 158, 11, 0.3); }
        .status-badge.highload { background: rgba(239, 68, 68, 0.15); color: var(--red); border: 1px solid rgba(239, 68, 68, 0.3); }
        .status-badge.offline { background: rgba(156, 163, 175, 0.15); color: var(--text-muted); border: 1px solid var(--border); }

        .metrics {
            display: flex;
            justify-content: space-between;
            align-items: baseline;
        }

        .user-count {
            font-size: 1.25rem;
            font-weight: 800;
            letter-spacing: -0.5px;
        }
        .user-count span { font-size: 0.85rem; font-weight: 500; color: var(--text-muted); }

        .progress-box {
            display: flex;
            flex-direction: column;
            gap: 0.35rem;
        }

        .progress-info {
            display: flex;
            justify-content: space-between;
            font-size: 0.75rem;
            color: var(--text-muted);
            font-weight: 500;
        }

        .progress-track {
            background: var(--border);
            height: 6px;
            border-radius: 10px;
            overflow: hidden;
        }

        .progress-fill {
            height: 100%;
            border-radius: 10px;
            transition: width 0.6s ease;
        }

        .bar-green { background: var(--green); box-shadow: 0 0 10px var(--glow-green); }
        .bar-yellow { background: var(--yellow); }
        .bar-red { background: var(--red); box-shadow: 0 0 10px var(--glow-red); }

        .status-dot {
            width: 10px;
            height: 10px;
            border-radius: 50%;
            display: inline-block;
        }
        .dot-green { background: var(--green); box-shadow: 0 0 8px var(--green); }
        .dot-yellow { background: var(--yellow); box-shadow: 0 0 8px var(--yellow); }
        .dot-red { background: var(--red); box-shadow: 0 0 8px var(--red); }

        .footer-note {
            text-align: center;
            margin-top: 3rem;
            color: var(--text-muted);
            font-size: 0.85rem;
            display: flex;
            justify-content: center;
            align-items: center;
            gap: 0.5rem;
        }

        @keyframes pulse {
            0% { transform: scale(0.95); opacity: 0.8; }
            50% { transform: scale(1.1); opacity: 1; }
            100% { transform: scale(0.95); opacity: 0.8; }
        }
        .pulse { animation: pulse 2s infinite; }
    </style>
</head>
<body>

    <nav class="navbar">
        <div class="nav-container">
            <a class="brand" href="#">
                <img src="https://pukangvpn.xyz/icon/server-online.png" alt="Logo">
                <span>CYBER<span style="color: var(--primary);">NODE</span></span>
            </a>
            <div class="nav-actions">
                <button class="theme-toggle" onclick="toggleTheme()" id="themeBtn" title="Toggle Theme">
                    <i class="bi bi-moon-stars-fill" id="themeIcon"></i>
                </button>
            </div>
        </div>
    </nav>

    <div class="main-container">
        <div class="dashboard-header">
            <div class="header-title">
                <h1><i class="bi bi-shield-lock-fill" style="color: var(--primary);"></i> Server Status Network</h1>
                <p>Real-time gateway monitoring and load balancing indicator</p>
            </div>
            <div class="total-card total-badge">
                <span class="status-dot pulse <?= getTotalDotClass($totalOnline) ?>"></span>
                <div>
                    <div style="font-size: 0.75rem; color: var(--text-muted); font-weight: 500;">TOTAL ACTIVE USERS</div>
                    <div style="font-size: 1.15rem; font-weight: 700;"><?= number_format($totalOnline) ?> <span style="font-size: 0.8rem; font-weight: normal; color: var(--text-muted);">Online</span></div>
                </div>
            </div>
        </div>

        <div class="server-grid">
            <?php foreach ($serverStatuses as $name => $data): ?>
                <?php if ($data['success']): ?>
                    <?php 
                        $online = $data['online'];
                        $percent = getPercentage($online, $maxCapacity);
                        $barColor = getBarColorClass($percent);
                    ?>
                    <div class="server-card">
                        <div class="card-top">
                            <span class="server-name"><i class="bi bi-hdd-rack" style="color: var(--text-muted);"></i> <?= htmlspecialchars($name) ?></span>
                            <span class="status-badge <?= getStatusClass($online) ?>"><?= getStatusText($online) ?></span>
                        </div>
                        <div class="metrics">
                            <div class="user-count">
                                <?= number_format($online) ?> <span>/ <?= $maxCapacity ?></span>
                            </div>
                            <span class="status-dot <?= getDotClass($online) ?>"></span>
                        </div>
                        <div class="progress-box">
                            <div class="progress-info">
                                <span>Load Capacity</span>
                                <span><?= $percent ?>%</span>
                            </div>
                            <div class="progress-track">
                                <div class="progress-fill <?= $barColor ?>" style="width: <?= $percent ?>%;"></div>
                            </div>
                        </div>
                    </div>
                <?php else: ?>
                    <div class="server-card" style="opacity: 0.6;">
                        <div class="card-top">
                            <span class="server-name"><i class="bi bi-hdd-rack" style="color: var(--text-muted);"></i> <?= htmlspecialchars($name) ?></span>
                            <span class="status-badge offline">OFFLINE</span>
                        </div>
                        <div class="metrics">
                            <div class="user-count" style="color: var(--text-muted);">
                                0 <span>/ <?= $maxCapacity ?></span>
                            </div>
                            <span class="status-dot dot-red"></span>
                        </div>
                        <div class="progress-box">
                            <div class="progress-info">
                                <span>Connection Failed</span>
                                <span>0%</span>
                            </div>
                            <div class="progress-track">
                                <div class="progress-fill" style="width: 0%;"></div>
                            </div>
                        </div>
                    </div>
                <?php endif; ?>
            <?php endforeach; ?>
        </div>

        <div class="footer-note">
            <i class="bi bi-arrow-repeat pulse"></i> Auto-refreshing every 30 seconds &bull; Max <?= $maxCapacity ?> users per node
        </div>
    </div>

    <script>
        function toggleTheme() {
            const html = document.documentElement;
            const icon = document.getElementById('themeIcon');
            if (html.classList.contains('dark')) {
                html.classList.remove('dark');
                html.classList.add('light');
                icon.className = 'bi bi-sun-fill';
                localStorage.setItem('theme', 'light');
            } else {
                html.classList.remove('light');
                html.classList.add('dark');
                icon.className = 'bi bi-moon-stars-fill';
                localStorage.setItem('theme', 'dark');
            }
        }

        // โหลดธีมที่ผู้ใช้เคยเลือกไว้ หรือตั้งค่าเริ่มต้นเป็น Dark
        const savedTheme = localStorage.getItem('theme') || 'dark';
        document.documentElement.className = savedTheme;
        if(savedTheme === 'light') {
            document.getElementById('themeIcon').className = 'bi bi-sun-fill';
        }

        // รีเฟรชหน้าเว็บทุกๆ 30 วินาที
        setTimeout(() => location.reload(), 30000);
    </script>
</body>
</html>
