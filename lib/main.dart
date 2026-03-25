import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'package:vibration/vibration.dart';
import 'package:flutter_animate/flutter_animate.dart';

// ==================== MAIN ====================
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  final securityService = SecurityService();
  await securityService.initialize();
  
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => GameModel()),
        ChangeNotifierProvider(create: (_) => BankModel()),
        Provider.value(value: securityService),
      ],
      child: const MinesIAApp(),
    ),
  );
}

class MinesIAApp extends StatelessWidget {
  const MinesIAApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MINES IA',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: Colors.black,
        primaryColor: const Color(0xFF00FF88),
      ),
      home: const GameScreen(),
    );
  }
}

// ==================== MODELS ====================
class Cell {
  final int row;
  final int col;
  bool isRevealed;
  bool isMine;
  bool isStar;
  bool isSuggested;
  
  Cell({
    required this.row,
    required this.col,
    this.isRevealed = false,
    this.isMine = false,
    this.isStar = false,
    this.isSuggested = false,
  });
  
  void reset() {
    isRevealed = false;
    isMine = false;
    isStar = false;
    isSuggested = false;
  }
}

class GameModel extends ChangeNotifier {
  static const int gridSize = 5;
  List<List<Cell>> grid = [];
  int minesCount = 5;
  int starsCount = 3;
  bool gameActive = true;
  String lastResult = '';
  
  GameModel() {
    initializeGrid();
  }
  
  void initializeGrid() {
    grid = List.generate(
      gridSize,
      (row) => List.generate(
        gridSize,
        (col) => Cell(row: row, col: col),
      ),
    );
    notifyListeners();
  }
  
  void setStrategy(int mines, int stars) {
    minesCount = mines;
    starsCount = stars;
    resetGame();
  }
  
  void resetGame() {
    for (var row in grid) {
      for (var cell in row) {
        cell.reset();
      }
    }
    gameActive = true;
    lastResult = '';
    notifyListeners();
  }
  
  void generatePlay() {
    if (!gameActive) {
      resetGame();
    }
    
    resetGame();
    
    // Posiciona minas
    int minesPlaced = 0;
    while (minesPlaced < minesCount) {
      int row = (DateTime.now().millisecondsSinceEpoch % gridSize).toInt();
      int col = ((DateTime.now().millisecondsSinceEpoch + minesPlaced) % gridSize).toInt();
      if (!grid[row][col].isMine && !grid[row][col].isStar) {
        grid[row][col].isMine = true;
        minesPlaced++;
      }
    }
    
    // Posiciona estrelas
    int starsPlaced = 0;
    while (starsPlaced < starsCount) {
      int row = ((DateTime.now().millisecondsSinceEpoch + starsPlaced * 10) % gridSize).toInt();
      int col = ((DateTime.now().millisecondsSinceEpoch + starsPlaced * 20) % gridSize).toInt();
      if (!grid[row][col].isMine && !grid[row][col].isStar) {
        grid[row][col].isStar = true;
        starsPlaced++;
      }
    }
    
    _generateSuggestions();
    notifyListeners();
  }
  
  void _generateSuggestions() {
    for (var row in grid) {
      for (var cell in row) {
        if (!cell.isMine && !cell.isStar) {
          cell.isSuggested = true;
        }
      }
    }
  }
  
  bool revealCell(int row, int col) {
    if (!gameActive) return false;
    if (grid[row][col].isRevealed) return false;
    
    grid[row][col].isRevealed = true;
    
    if (grid[row][col].isMine) {
      lastResult = 'ERROU';
      gameActive = false;
      notifyListeners();
      return false;
    } else if (grid[row][col].isStar) {
      lastResult = 'ACERTOU';
      notifyListeners();
      return true;
    }
    
    lastResult = 'ACERTOU';
    notifyListeners();
    return true;
  }
}

class BankModel extends ChangeNotifier {
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  
  double bank = 100.0;
  double bet = 5.0;
  double stopLoss = 70.0;
  
  static const String _bankKey = 'bank_value';
  static const String _stopLossKey = 'stop_loss';
  
  BankModel() {
    _loadData();
  }
  
  Future<void> _loadData() async {
    final savedBank = await _storage.read(key: _bankKey);
    final savedStopLoss = await _storage.read(key: _stopLossKey);
    
    if (savedBank != null) bank = double.parse(savedBank);
    if (savedStopLoss != null) stopLoss = double.parse(savedStopLoss);
    
    notifyListeners();
  }
  
  Future<void> _saveBank() async {
    await _storage.write(key: _bankKey, value: bank.toString());
  }
  
  void setBetPercentage(double percentage) {
    bet = bank * (percentage / 100);
    bet = double.parse(bet.toStringAsFixed(2));
    notifyListeners();
  }
  
  void updateBet(double newBet) {
    bet = newBet;
    notifyListeners();
  }
  
  bool processWin() {
    double winAmount = bet * 0.5;
    bank += winAmount;
    bank = double.parse(bank.toStringAsFixed(2));
    _saveBank();
    notifyListeners();
    return bank >= stopLoss;
  }
  
  bool processLoss() {
    bank -= bet;
    bank = double.parse(bank.toStringAsFixed(2));
    _saveBank();
    notifyListeners();
    return bank >= stopLoss;
  }
  
  double get profit => bank - 100.0;
  bool get isStopLossReached => bank <= stopLoss;
}

// ==================== SERVICES ====================
class SecurityService {
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  static const String _licenseKey = 'app_license';
  
  Future<void> initialize() async {
    final license = await _storage.read(key: _licenseKey);
    if (license == null) {
      await _createFreeLicense();
    }
  }
  
  Future<void> _createFreeLicense() async {
    final licenseData = {
      'type': 'free',
      'expires': DateTime.now().add(const Duration(days: 30)).toIso8601String(),
    };
    await _storage.write(key: _licenseKey, value: jsonEncode(licenseData));
  }
  
  Future<bool> validateLicense() async {
    final license = await _storage.read(key: _licenseKey);
    if (license == null) return false;
    return true;
  }
}

// ==================== SCREENS ====================
class GameScreen extends StatelessWidget {
  const GameScreen({super.key});
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.center,
            radius: 1.5,
            colors: [Color(0xFF0A0A2A), Color(0xFF000000)],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            child: Column(
              children: [
                const SizedBox(height: 20),
                const Text(
                  'MINES IA',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 4,
                    color: Color(0xFF00FF88),
                    shadows: [Shadow(blurRadius: 20, color: Color(0xFF00FF88))],
                  ),
                ),
                const SizedBox(height: 20),
                
                // Painel de Estratégia
                Consumer<GameModel>(
                  builder: (context, game, _) => StrategyPanel(game: game),
                ),
                const SizedBox(height: 20),
                
                // Grade 5x5
                Consumer<GameModel>(
                  builder: (context, game, _) => GridWidget(game: game),
                ),
                const SizedBox(height: 20),
                
                // Botão GERAR JOGADA
                Consumer<GameModel>(
                  builder: (context, game, _) => GestureDetector(
                    onTap: () => game.generatePlay(),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF00FF88), Color(0xFF00AA55)],
                        ),
                        borderRadius: BorderRadius.circular(40),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF00FF88).withOpacity(0.5),
                            blurRadius: 20,
                          ),
                        ],
                      ),
                      child: const Text(
                        'GERAR JOGADA',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                
                // Feedback
                Consumer<GameModel>(
                  builder: (context, game, _) => ResultFeedback(result: game.lastResult),
                ),
                const SizedBox(height: 20),
                
                // Painel de Banca
                Consumer<BankModel>(
                  builder: (context, bank, _) => BankPanel(bank: bank),
                ),
                const SizedBox(height: 30),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ==================== WIDGETS ====================
class GridWidget extends StatelessWidget {
  final GameModel game;
  
  const GridWidget({super.key, required this.game});
  
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedNumberOfCrossAxisCount(
          crossAxisCount: 5,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
        ),
        itemCount: 25,
        itemBuilder: (context, index) {
          int row = index ~/ 5;
          int col = index % 5;
          Cell cell = game.grid[row][col];
          
          return GestureDetector(
            onTap: () async {
              if (!game.gameActive) return;
              bool isWin = game.revealCell(row, col);
              final bank = context.read<BankModel>();
              if (isWin) {
                bank.processWin();
              } else {
                bank.processLoss();
              }
              if (bank.isStopLossReached) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('⚠️ Stop Loss atingido!'), backgroundColor: Colors.red),
                );
              }
              if (await Vibration.hasVibrator() ?? false) {
                Vibration.vibrate(duration: isWin ? 50 : 100);
              }
            },
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: cell.isRevealed
                      ? (cell.isMine
                          ? [Colors.red.shade900, Colors.red.shade800]
                          : cell.isStar
                              ? [Colors.green.shade900, Colors.green.shade800]
                              : [Colors.grey.shade800, Colors.grey.shade900])
                      : [Colors.grey.shade900, Colors.black87],
                ),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: cell.isSuggested ? Colors.green.shade400 : Colors.cyan.shade400.withOpacity(0.5),
                  width: cell.isSuggested ? 2 : 1,
                ),
              ),
              child: Center(
                child: Icon(
                  cell.isRevealed
                      ? (cell.isMine ? Icons.bomb : cell.isStar ? Icons.star : Icons.circle_outlined)
                      : Icons.circle_outlined,
                  color: cell.isRevealed
                      ? Colors.white
                      : (cell.isSuggested ? Colors.green.shade300 : Colors.grey.shade500),
                  size: 28,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class StrategyPanel extends StatelessWidget {
  final GameModel game;
  
  const StrategyPanel({super.key, required this.game});
  
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _StrategyCard(
          title: '⚠️ 5 minas',
          subtitle: '3 estrelas',
          isActive: game.minesCount == 5,
          onTap: () => game.setStrategy(5, 3),
        ),
        const SizedBox(width: 20),
        _StrategyCard(
          title: '⭐ 3 minas',
          subtitle: '4 estrelas',
          isActive: game.minesCount == 3,
          onTap: () => game.setStrategy(3, 4),
        ),
      ],
    );
  }
}

class _StrategyCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool isActive;
  final VoidCallback onTap;
  
  const _StrategyCard({
    required this.title,
    required this.subtitle,
    required this.isActive,
    required this.onTap,
  });
  
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isActive ? [Colors.green.shade800, Colors.green.shade900] : [Colors.grey.shade800, Colors.grey.shade900],
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isActive ? Colors.green.shade400 : Colors.grey.shade600),
        ),
        child: Column(
          children: [
            Text(title, style: TextStyle(color: isActive ? Colors.green.shade300 : Colors.white70)),
            Text(subtitle, style: TextStyle(color: isActive ? Colors.green.shade200 : Colors.grey.shade400, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

class BankPanel extends StatelessWidget {
  final BankModel bank;
  
  const BankPanel({super.key, required this.bank});
  
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.black.withOpacity(0.8), Colors.grey.shade900.withOpacity(0.8)],
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _InfoCard(title: 'Banco', value: 'R\$ ${bank.bank.toStringAsFixed(2)}', color: Colors.green),
              _InfoCard(title: 'Lucro', value: 'R\$ ${bank.profit.toStringAsFixed(2)}', color: bank.profit >= 0 ? Colors.green : Colors.red),
              _InfoCard(title: 'Stop Loss', value: 'R\$ ${bank.stopLoss.toStringAsFixed(2)}', color: Colors.red),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('Aposta: R\$ ', style: TextStyle(color: Colors.white70)),
              Container(
                width: 80,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: TextField(
                  controller: TextEditingController(text: bank.bet.toStringAsFixed(2)),
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 8)),
                  onChanged: (value) {
                    double? newBet = double.tryParse(value);
                    if (newBet != null) bank.updateBet(newBet);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _PercentButton(percent: 1, bank: bank),
              _PercentButton(percent: 2, bank: bank),
              _PercentButton(percent: 5, bank: bank),
              _PercentButton(percent: 10, bank: bank),
            ],
          ),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final String title;
  final String value;
  final Color color;
  
  const _InfoCard({required this.title, required this.value, required this.color});
  
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(title, style: TextStyle(color: Colors.grey.shade400, fontSize: 12)),
        const SizedBox(height: 4),
        Text(value, style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.bold)),
      ],
    );
  }
}

class _PercentButton extends StatelessWidget {
  final int percent;
  final BankModel bank;
  
  const _PercentButton({required this.percent, required this.bank});
  
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => bank.setBetPercentage(percent),
      child: Container(
        width: 50,
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [Colors.grey.shade800, Colors.grey.shade900]),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(child: Text('$percent%', style: const TextStyle(color: Colors.white))),
      ),
    );
  }
}

class ResultFeedback extends StatelessWidget {
  final String result;
  
  const ResultFeedback({super.key, required this.result});
  
  @override
  Widget build(BuildContext context) {
    if (result.isEmpty) return const SizedBox(height: 50);
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: result == 'ACERTOU' ? [Colors.green.shade700, Colors.green.shade900] : [Colors.red.shade700, Colors.red.shade900],
        ),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(result == 'ACERTOU' ? Icons.check_circle : Icons.cancel, color: Colors.white, size: 28),
          const SizedBox(width: 10),
          Text(result, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white)),
        ],
      ),
    );
  }
}
