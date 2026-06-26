<?php
// --- Proxy function ---
function fetchOnlineCount($url) {
    $allowed_domains = [
        'nn01.pukangvpn.xyz',
        'nn02.pukangvpn.xyz',
        'nn03.pukangvpn.xyz',
        'nn04.pukangvpn.xyz',
        'nn05.pukangvpn.xyz',
        'nn06.pukangvpn.xyz',
        'nn07.pukangvpn.xyz',
        'nn08.pukangvpn.xyz', 
        'nn09.pukangvpn.xyz',
        'nn10.pukangvpn.xyz', 
        'nn11.pukangvpn.xyz', 
        'nn12.pukangvpn.xyz',
        'nn13.pukangvpn.xyz', 
        'nn14.pukangvpn.xyz',
        'nn15.pukangvpn.xyz',
        'nn16.pukangvpn.xyz',
        'nn17.pukangvpn.xyz',
        'nn18.pukangvpn.xyz',
        'nn19.pukangvpn.xyz',
        'nn20.pukangvpn.xyz',
        'nn21.pukangvpn.xyz',
        'nn22.pukangvpn.xyz',
        'nn23.pukangvpn.xyz',
        'nn24.pukangvpn.xyz',
        'nn25.pukangvpn.xyz'
    ];
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

$servers = [
    
    ' THAILAND-01' => ['http://nn01.pukangvpn.xyz:82/server/online', 'http://nn01.pukangvpn.xyz:82/udpserver/online'],
    ' THAILAND-02' => ['http://nn02.pukangvpn.xyz:82/server/online', 'http://nn02.pukangvpn.xyz:82/udpserver/online'],
    ' THAILAND-03' => ['http://nn03.pukangvpn.xyz:82/server/online', 'http://nn03.pukangvpn.xyz:82/udpserver/online'],
    ' THAILAND-04' => ['http://nn04.pukangvpn.xyz:82/server/online', 'http://nn04.pukangvpn.xyz:82/udpserver/online'],
    ' THAILAND-05' => ['http://nn05.pukangvpn.xyz:82/server/online', 'http://nn05.pukangvpn.xyz:82/udpserver/online'],
    ' THAILAND-06' => ['http://nn06.pukangvpn.xyz:82/server/online', 'http://nn06.pukangvpn.xyz:82/udpserver/online'],
    ' THAILAND-07' => ['http://nn07.pukangvpn.xyz:82/server/online', 'http://nn07.pukangvpn.xyz:82/udpserver/online'],
    ' THAILAND-08' => ['http://nn08.pukangvpn.xyz:82/server/online', 'http://nn08.pukangvpn.xyz:82/udpserver/online'],
    ' THAILAND-09' => ['http://nn09.pukangvpn.xyz:82/server/online', 'http://nn09.pukangvpn.xyz:82/udpserver/online'],
    ' THAILAND-10' => ['http://nn10.pukangvpn.xyz:82/server/online', 'http://nn10.pukangvpn.xyz:82/udpserver/online'],
    ' THAILAND-11' => ['http://nn11.pukangvpn.xyz:82/server/online', 'http://nn11.pukangvpn.xyz:82/udpserver/online'],
    ' THAILAND-12' => ['http://nn12.pukangvpn.xyz:82/server/online', 'http://nn12.pukangvpn.xyz:82/udpserver/online'],
    ' THAILAND-13' => ['http://nn13.pukangvpn.xyz:82/server/online', 'http://nn13.pukangvpn.xyz:82/udpserver/online'],
    ' THAILAND-14' => ['http://nn14.pukangvpn.xyz:82/server/online', 'http://nn14.pukangvpn.xyz:82/udpserver/online'],
    ' THAILAND-15' => ['http://nn15.pukangvpn.xyz:82/server/online', 'http://nn15.pukangvpn.xyz:82/udpserver/online'],
    ' THAILAND-16' => ['http://nn16.pukangvpn.xyz:82/server/online', 'http://nn16.pukangvpn.xyz:82/udpserver/online'],
    ' THAILAND-17' => ['http://nn17.pukangvpn.xyz:82/server/online', 'http://nn17.pukangvpn.xyz:82/udpserver/online'],
    ' THAILAND-18' => ['http://nn18.pukangvpn.xyz:82/server/online', 'http://nn18.pukangvpn.xyz:82/udpserver/online'],
    ' THAILAND-19' => ['http://nn19.pukangvpn.xyz:82/server/online', 'http://nn19.pukangvpn.xyz:82/udpserver/online'],
    ' THAILAND-20' => ['http://nn20.pukangvpn.xyz:82/server/online', 'http://nn20.pukangvpn.xyz:82/udpserver/online'],
    ' THAILAND-21' => ['http://nn21.pukangvpn.xyz:82/server/online', 'http://nn21.pukangvpn.xyz:82/udpserver/online'],
    ' THAILAND-22' => ['http://nn22.pukangvpn.xyz:82/server/online', 'http://nn22.pukangvpn.xyz:82/udpserver/online'],
    ' THAILAND-23' => ['http://nn23.pukangvpn.xyz:82/server/online', 'http://nn23.pukangvpn.xyz:82/udpserver/online'],
    ' THAILAND-24' => ['http://nn24.pukangvpn.xyz:82/server/online', 'http://nn24.pukangvpn.xyz:82/udpserver/online'],
    ' THAILAND-25' => ['http://nn25.pukangvpn.xyz:82/server/online', 'http://nn25.pukangvpn.xyz:82/udpserver/online'],
];

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
    if ($online > 200) return 'High Load';
    if ($online > 150) return 'Busy';
    return 'Normal';
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

/*  progress bar  */
function getBarColorClass($percent) {
    if ($percent >= 95) return 'bar-red';      // 95-100%  
    if ($percent >= 50) return 'bar-yellow';   // 50-94%  
    return 'bar-green';                        // 1-49%  
}

header("Content-Security-Policy: frame-ancestors *;");
?>
<!DOCTYPE html>
<html lang="th">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Server Status Online User</title>
    <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bootstrap-icons@1.11.3/font/bootstrap-icons.min.css">
    <link href="https://fonts.googleapis.com/css2?family=Inter:opsz,wght@14..32,400;14..32,500;14..32,600;14..32,700&display=swap" rel="stylesheet">
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        :root {
            --bg-light: #f4f7fb;
            --surface-light: #ffffff;
            --text-primary-light: #1e293b;
            --text-secondary-light: #64748b;
            --border-light: #e2e8f0;
            --card-shadow-light: 0 10px 25px -5px rgba(0,0,0,0.05), 0 8px 10px -6px rgba(0,0,0,0.02);
            --nav-bg-light: rgba(255,255,255,0.8);
            --bg-dark: #0b1120;
            --surface-dark: #1e293b;
            --text-primary-dark: #f1f5f9;
            --text-secondary-dark: #94a3b8;
            --border-dark: #334155;
            --card-shadow-dark: 0 20px 25px -5px rgba(0,0,0,0.5), 0 8px 10px -6px rgba(0,0,0,0.3);
            --nav-bg-dark: rgba(15, 23, 42, 0.8);
            --green: #10b981;
            --yellow: #f59e0b;
            --red: #ef4444;
            --grey: #94a3b8;
            --bar-bg: #e2e8f0;
            --space-xs: 0.5rem;
            --space-sm: 0.75rem;
            --space-md: 1rem;
            --space-lg: 1.5rem;
            --space-xl: 2rem;
            --bg: var(--bg-light);
            --surface: var(--surface-light);
            --text-primary: var(--text-primary-light);
            --text-secondary: var(--text-secondary-light);
            --border: var(--border-light);
            --card-shadow: var(--card-shadow-light);
            --nav-bg: var(--nav-bg-light);
        }
        body.dark-mode {
            --bg: var(--bg-dark);
            --surface: var(--surface-dark);
            --text-primary: var(--text-primary-dark);
            --text-secondary: var(--text-secondary-dark);
            --border: var(--border-dark);
            --card-shadow: var(--card-shadow-dark);
            --nav-bg: var(--nav-bg-dark);
            --bar-bg: #334155;
        }
        body {
            font-family: 'Inter', sans-serif;
            background: var(--bg);
            color: var(--text-primary);
            min-height: 100vh;
            transition: background 0.3s, color 0.2s;
            line-height: 1.5;
            padding: 0 0 var(--space-lg) 0;
        }
        .navbar {
            position: sticky;
            top: 0;
            backdrop-filter: blur(12px);
            background: var(--nav-bg) !important;
            border-bottom: 1px solid var(--border);
            padding: 0.75rem 1.5rem;
            z-index: 10;
        }
        .navbar .container {
            display: flex;
            align-items: center;
            justify-content: space-between;
            flex-wrap: wrap;
            max-width: 1280px;
            margin: 0 auto;
        }
        .navbar-brand {
            display: flex;
            align-items: center;
            gap: var(--space-xs);
            font-weight: 700;
            font-size: 1.5rem;
            color: var(--text-primary);
            text-decoration: none;
        }
        .navbar-brand img {
            width: 36px;
            height: auto;
        }
        .main {
            max-width: 1280px;
            margin: var(--space-xl) auto 0;
            padding: 0 var(--space-lg);
        }
        .status-header {
            display: flex;
            justify-content: flex-end;
            margin-bottom: var(--space-xl);
        }
        .total-card {
            background: var(--surface);
            padding: var(--space-sm) var(--space-lg);
            border-radius: 100px;
            box-shadow: var(--card-shadow);
            border: 1px solid var(--border);
            display: flex;
            align-items: center;
            gap: var(--space-sm);
            font-weight: 600;
            font-size: 1.2rem;
        }
        .total-card .status-dot { width: 14px; height: 14px; }
        .server-grid {
            display: grid;
            grid-template-columns: repeat(auto-fill, minmax(320px, 1fr));
            gap: var(--space-lg);
        }
        .server-card {
            background: var(--surface);
            border-radius: 24px;
            padding: var(--space-lg);
            box-shadow: var(--card-shadow);
            border: 1px solid var(--border);
            transition: transform 0.2s, box-shadow 0.2s;
            display: flex;
            flex-direction: column;
            gap: var(--space-md);
        }
        .server-card:hover {
            transform: translateY(-4px);
            box-shadow: 0 25px 35px -12px rgba(0,0,0,0.15);
        }
        .card-header {
            display: flex;
            align-items: center;
            gap: var(--space-sm);
        }
        .server-name {
            font-weight: 700;
            font-size: 1.25rem;
            display: flex;
            align-items: center;
            gap: 0.4rem;
        }
        .server-name i { color: var(--text-secondary); }
        .status-badge {
            margin-left: auto;
            font-size: 0.8rem;
            font-weight: 600;
            padding: 0.2rem 0.8rem;
            border-radius: 30px;
            background: var(--bg);
            border: 1px solid var(--border);
            color: var(--text-secondary);
        }
        .status-badge.highload { color: #ef4444; }
        .status-badge.busy { color: #f59e0b; }
        .status-badge.normal { color: #10b981; }
        .status-line {
            display: flex;
            align-items: baseline;
            gap: var(--space-sm);
            flex-wrap: wrap;
        }
        .online-count {
            font-weight: 700;
            color: var(--text-primary);
            background: var(--bg);
            padding: 0.2rem 0.6rem;
            border-radius: 20px;
            font-size: 0.9rem;
        }
        .status-dot {
            display: inline-block;
            width: 12px;
            height: 12px;
            border-radius: 50%;
        }
        .dot-green { background: var(--green); }
        .dot-yellow { background: var(--yellow); }
        .dot-red { background: var(--red); }
        .dot-grey { background: var(--grey); }
        .percentage-container {
            margin-top: 0.25rem;
        }
        .percentage-label {
            display: flex;
            justify-content: space-between;
            font-size: 0.75rem;
            margin-bottom: 0.25rem;
            color: var(--text-secondary);
        }
        .bar-bg {
            background-color: var(--bar-bg);
            border-radius: 12px;
            height: 8px;
            overflow: hidden;
            width: 100%;
        }
        .bar-fill {
            height: 100%;
            width: 0%;
            border-radius: 12px;
            transition: width 0.4s ease;
        }
        .bar-green { background-color: #10b981; }
        .bar-yellow { background-color: #f59e0b; }
        .bar-red { background-color: #ef4444; }
        .offline-message {
            color: var(--text-secondary);
            font-style: italic;
            display: flex;
            align-items: center;
            gap: var(--space-sm);
        }
        .footer-note {
            text-align: center;
            margin-top: var(--space-xl);
            color: var(--text-secondary);
            font-size: 0.9rem;
        }
        @media (max-width: 640px) {
            .navbar .container { flex-direction: column; align-items: stretch; gap: var(--space-sm); }
            .status-header { justify-content: center; }
            .total-card { align-self: stretch; justify-content: center; }
        }
    </style>
</head>
<body>
    <nav class="navbar">
        <div class="container">
            <a class="navbar-brand" href="#">
                <img src="https://pukangvpn.xyz/icon/server-online.png" alt="Status">
                Server Online User
            </a>
        </div>
    </nav>

    <div class="main">
        <div class="status-header">
            <div class="total-card">
                <span class="status-dot <?= getTotalDotClass($totalOnline) ?>"></span>
                <span class="online-count"><?= number_format($totalOnline) ?> total online</span>
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
                        <div class="card-header">
                            <span class="server-name"><i class="bi bi-hdd-stack"></i> <?= htmlspecialchars($name) ?></span>
                            <span class="status-badge <?= getStatusClass($online) ?>"><?= getStatusText($online) ?></span>
                        </div>
                        <div class="status-line">
                            <span class="status-dot <?= getDotClass($online) ?>"></span>
                            <span class="online-count"><?= number_format($online) ?> / <?= $maxCapacity ?> users</span>
                        </div>
                        <div class="percentage-container">
                            <div class="percentage-label">
                                <span>Utilization</span>
                                <span><?= $percent ?>%</span>
                            </div>
                            <div class="bar-bg">
                                <div class="bar-fill <?= $barColor ?>" style="width: <?= $percent ?>%;"></div>
                            </div>
                        </div>
                    </div>
                <?php else: ?>
                    <div class="server-card">
                        <div class="card-header">
                            <span class="server-name"><i class="bi bi-hdd-stack"></i> <?= htmlspecialchars($name) ?></span>
                            <span class="status-badge"></span>
                        </div>
                        <div class="offline-message">
                            <span class="status-dot dot-red"></span>
                            Unable to connect
                        </div>
                        <div class="percentage-container">
                            <div class="percentage-label">
                                <span>Utilization</span>
                                <span>�</span>
                            </div>
                            <div class="bar-bg">
                                <div class="bar-fill" style="width: 0%;"></div>
                            </div>
                        </div>
                    </div>
                <?php endif; ?>
            <?php endforeach; ?>
        </div>

        <div class="footer-note">
            <i class="bi bi-arrow-repeat me-1"></i> Auto-refresh every 30 seconds � Max <?= $maxCapacity ?> users per server
        </div>
    </div>

    <script>
        function applyTheme(theme) {
            if (theme === 'dark') {
                document.body.classList.add('dark-mode');
            } else {
                document.body.classList.remove('dark-mode');
            }
        }
        function getThemeByTime() {
            const hours = new Date().getHours();
            return (hours >= 6 && hours < 18) ? 'light' : 'dark';
        }
        applyTheme(getThemeByTime());
        setTimeout(() => location.reload(), 30000);
    </script>
</body>
</html>