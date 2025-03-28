import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:url_launcher/url_launcher.dart';
import 'dart:async';

void main() {
  runApp(BoatRaceApp());
}

class BoatRaceApp extends StatefulWidget {
  @override
  _BoatRaceAppState createState() => _BoatRaceAppState();
}

class _BoatRaceAppState extends State<BoatRaceApp> {
  final String apiUrl = "http://127.0.0.1:5001/api/missing-races";
  Map<String, List<String>> missingRaces = {};
  bool isLoading = true;
  Timer? _timer;
  String lastSentMessage = "";

  @override
  void initState() {
    super.initState();
    fetchData();
    _timer = Timer.periodic(Duration(minutes: 30), (timer) {
      int nowHour = DateTime.now().hour;
      if (nowHour >= 7 && nowHour < 23) {
        fetchData();
      } else {
        debugPrint("⏳ 自動更新停止中 (23:00〜7:00)");
      }
    });
  }

  Future<void> fetchData() async {
  try {
    debugPrint("🔄 APIリクエスト送信中...");
    final response =
        await http.get(Uri.parse(apiUrl)).timeout(Duration(seconds: 120));

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data == null || data["missing_races"] == null) {
        throw Exception("APIレスポンスに missing_races が含まれていません");
      }

      setState(() {
        Map<String, List<String>> extractedData = {};
        data["missing_races"].forEach((place, raceLinks) {
          if (raceLinks is List) {
            List<String> validUrls = [];
            for (var item in raceLinks) {
              if (item is List && item.length > 1 && item[1] is String) {
                validUrls.add(item[1]); // URLを抽出
              } else if (item is String) {
                validUrls.add(item);
              }
            }
            extractedData[place] = validUrls;
          }
        });

        debugPrint("🎯 抽出後の欠場URL: $extractedData");
        missingRaces = extractedData;
        isLoading = false;
      });


      final Map<String, String> placeOrder = {
        "01": "桐生", "02": "戸田", "03": "江戸川", "04": "平和島", "05": "多摩川",
        "06": "浜名湖", "07": "蒲郡", "08": "常滑", "09": "津", "10": "三国",
        "11": "びわこ", "12": "住之江", "13": "尼崎", "14": "鳴門", "15": "丸亀",
        "16": "児島", "17": "宮島", "18": "徳山", "19": "下関", "20": "若松",
        "21": "芦屋", "22": "福岡", "23": "からつ", "24": "大村"
      };

      // 逆引き用の Map（場名 → 場コード）
      final Map<String, String> reversePlaceOrder = {
        for (var entry in placeOrder.entries) entry.value: entry.key
      };


      // 🔽 欠場のある場のみを場コード順にソート
      List<String> sortedPlaces = missingRaces.keys.toList()
        ..sort((a, b) {
          String codeA = reversePlaceOrder[a] ?? "99"; // デフォルト値を設定
          String codeB = reversePlaceOrder[b] ?? "99";
          return int.parse(codeA).compareTo(int.parse(codeB));
        });



      // 🔽 欠場のある場のみフィルタ
      List<String> filteredMessages = sortedPlaces
          .where((place) => missingRaces[place]!.isNotEmpty)
          .map((place) => "$place:\n${missingRaces[place]!.join('\n')}")
          .toList();

      // 🔽 欠場のある場が存在する場合のみメッセージ送信
      if (filteredMessages.isNotEmpty) {
        String message = "◼︎欠場情報\n" + filteredMessages.join("\n\n");

        // ✅ 前回のメッセージと異なる場合のみ通知
        if (message != lastSentMessage) {
          sendLineMessage(message);
          lastSentMessage = message; // ✅ 送信後に更新
        } else {
          debugPrint("🔕 変更なしのため通知をスキップ");
        }
      } else {
        debugPrint("🔕 欠場なしのため通知をスキップ");
      }
    }
  } catch (e) {
    debugPrint("❌ エラー: $e");
    setState(() {
      isLoading = false;
    });
  }
}

  Future<void> sendLineMessage(String message) async {
    final String accessToken =
        "ImwQWlSN13TeX3UUkC9VB2cbh4j1iwqEDwA2L5eUz89AF0EP1E1xdf6cONRowJSOzPaGDQerqS7FCZWHx0U1Kgc020q9ddVtp+xkaLPJ/8VjT0SrdbpSdpkBFIb5hL38aDti/M2rBF/Xed4fk/wbpgdB04t89/1O/w1cDnyilFU=";
    final String userId = "Uf74bf6e8604d060fce4a7ef910ac9f30";

    final url = Uri.parse("https://api.line.me/v2/bot/message/push");
    final headers = {
      "Content-Type": "application/json",
      "Authorization": "Bearer $accessToken",
    };
    final body = jsonEncode({
      "to": userId,
      "messages": [
        {
          "type": "text",
          "text": message,
        }
      ],
    });

    try {
      final response = await http.post(url, headers: headers, body: body);
      if (response.statusCode == 200) {
        debugPrint("✅ LINE通知送信成功");
      } else {
        debugPrint("❌ LINE通知送信失敗: ${response.statusCode} ${response.body}");
      }
    } catch (e) {
      debugPrint("⚠️ LINE通知送信エラー: $e");
    }
  }

  void _openRacePage(String url) async {
    Uri uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      debugPrint("❌ URLを開けません: $url");
    }
  }

  void _showRaceDetails(BuildContext context, String place) {
    List<String>? raceUrls = missingRaces[place];
    if (raceUrls == null || raceUrls.isEmpty) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("$place の欠場レース一覧"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: raceUrls.map((url) {
            return url.isNotEmpty && url.startsWith("http")
                ? TextButton(
                    onPressed: () => _openRacePage(url),
                    child: Text(url, style: TextStyle(color: Colors.blue)),
                  )
                : SizedBox.shrink();
          }).toList(),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: Text("閉じる"))
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        appBar: AppBar(
          title: Text("ボートレース 欠場情報"),
          backgroundColor: Colors.blue,
        ),
        body: isLoading
            ? Center(child: CircularProgressIndicator())
            : missingRaces.isEmpty
                ? Center(child: Text("欠場情報はありません"))
                : Padding(
                    padding: EdgeInsets.all(8.0),
                    child: GridView.builder(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 4,
                        childAspectRatio: 1,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 8,
                      ),
                      itemCount: missingRaces.length,
                      itemBuilder: (context, index) {
                        String place = missingRaces.keys.elementAt(index);
                        List<String>? urls = missingRaces[place];

                        return ElevatedButton(
                          onPressed: urls != null && urls.isNotEmpty
                              ? () => _showRaceDetails(context, place)
                              : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            padding: EdgeInsets.all(12.0),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                place,
                                style: TextStyle(fontSize: 16, color: Colors.white),
                              ),
                              Padding(
                                padding: EdgeInsets.only(top: 5),
                                child: Text(
                                  "${urls?.length ?? 0}件",
                                  style: TextStyle(fontSize: 14, color: Colors.white),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
        floatingActionButton: FloatingActionButton(
          onPressed: fetchData,
          child: Icon(Icons.refresh),
          backgroundColor: Colors.blue,
        ),
      ),
    );
  }
}
