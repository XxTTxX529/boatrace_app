import ssl
import requests
from bs4 import BeautifulSoup
from flask import Flask, jsonify, request
from flask_cors import CORS
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime

# **SSL証明書の検証を無効化**
ssl._create_default_https_context = ssl._create_unverified_context

app = Flask(__name__)
CORS(app)  # CORS設定追加

HEADERS = {
    "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/100.0.4896.127 Safari/537.36",
    "Referer": "https://www.boatrace.jp/",
    "Accept-Language": "ja,en;q=0.9",
}

BOAT_RACE_CODES = {
    "01": "桐生", "02": "戸田", "03": "江戸川", "04": "平和島", "05": "多摩川",
    "06": "浜名湖", "07": "蒲郡", "08": "常滑", "09": "津", "10": "三国",
    "11": "びわこ", "12": "住之江", "13": "尼崎", "14": "鳴門", "15": "丸亀",
    "16": "児島", "17": "宮島", "18": "徳山", "19": "下関", "20": "若松",
    "21": "芦屋", "22": "福岡", "23": "からつ", "24": "大村"
}

# **開催レースのURLを取得**
def get_race_links():
    url = "https://www.boatrace.jp/owpc/pc/race/index"
    print(f"🔄 開催情報ページ取得中: {url}")
    
    try:
        response = requests.get(url, headers=HEADERS, timeout=10)
        response.raise_for_status()
        soup = BeautifulSoup(response.text, "html.parser")

        race_links = {}
        race_table = soup.select("a[href*='racelist']")

        for link in race_table:
            href = link["href"]
            jcd = href.split("jcd=")[-1].split("&")[0]
            if jcd in BOAT_RACE_CODES:
                race_links[BOAT_RACE_CODES[jcd]] = f"https://www.boatrace.jp{href}"

        return race_links
    except requests.exceptions.RequestException as e:
        print(f"❌ エラー（レース情報取得失敗）: {e}")
        return {}

# **欠場選手のチェック**
def check_missing_race(url, place_name, race_no):
    print(f"🔄 ページ読み込み中: {url}")
    try:
        response = requests.get(url, headers=HEADERS, timeout=5)
        response.raise_for_status()
        
        soup = BeautifulSoup(response.text, "html.parser")
        black_elements = soup.select(".is-miss")

        if black_elements:
            print(f"✅ 欠場あり: {url} ({place_name} レース{race_no})")
            return place_name, race_no, url
    except requests.exceptions.Timeout:
        print(f"⏳ タイムアウト: {url}（再試行しません）")
    except requests.exceptions.RequestException as e:
        print(f"❌ エラー: {url} → {e}")
    return place_name, None, None  # 欠場なし

# **APIエンドポイント（欠場情報取得）**
@app.route("/api/missing-races", methods=["GET"])
def get_missing_races():
    date = request.args.get("date", None)  # ?date=YYYYMMDD で過去データ取得可能
    race_links = get_race_links()
    missing_races = {place: [] for place in BOAT_RACE_CODES.values()}  # 初期化

    urls = [
        (f"https://www.boatrace.jp/owpc/pc/race/racelist?rno={rno}&jcd={code}&hd={date or datetime.today().strftime('%Y%m%d')}", place, rno)
        for code, place in BOAT_RACE_CODES.items() for rno in range(1, 13)
    ]

    with ThreadPoolExecutor(max_workers=10) as executor:
        results = executor.map(lambda x: check_missing_race(x[0], x[1], x[2]), urls)

    for place, race_no, url in results:
        if race_no:
            missing_races[place].append((race_no, url))

    return jsonify({
        "updated_at": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
        "missing_races": missing_races,
        "race_links": race_links,
    })

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5001, threaded=True, debug=True)