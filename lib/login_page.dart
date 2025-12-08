import 'package:flutter/material.dart';
import '../database/database_helper.dart'; // 匯入資料庫管理類別

import 'package:flutter/material.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({Key? key}) : super(key: key);

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController usernameController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();

  bool isLoading = false;

  void _login() async {
    final username = usernameController.text.trim();
    final password = passwordController.text;

    if (username.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('請輸入帳號與密碼')),
      );
      return;
    }

    setState(() => isLoading = true);

    try {
      final user = await DatabaseHelper.instance.getUserByUsername(username);
      if (user == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('使用者不存在')),
        );
        return;
      }

      if (user['password'] != password) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('密碼錯誤')),
        );
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('登入成功！歡迎 ${user['name']}')),
      );

      // 登入成功後傳回 userId 或其他資料給上一頁
      Navigator.pop(context, {
        'userId': user['userId'],
        'name': user['name'],
      });
    } finally {
      setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('登入')),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            TextField(
              controller: usernameController,
              decoration: const InputDecoration(labelText: '帳號'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: passwordController,
              decoration: const InputDecoration(labelText: '密碼'),
              obscureText: true,
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: isLoading ? null : _login,
              child: isLoading
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text('登入'),
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const RegisterPage()),
                );
              },
              child: const Text('還沒有帳號？註冊'),
            ),
          ],
        ),
      ),
    );
  }
}

class RegisterPage extends StatelessWidget {
  const RegisterPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final TextEditingController usernameController = TextEditingController();
    final TextEditingController passwordController = TextEditingController();
    final TextEditingController confirmController = TextEditingController();
    final TextEditingController nameController = TextEditingController();

    return Scaffold(
      appBar: AppBar(title: const Text('註冊')),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: '名稱'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: usernameController,
              decoration: const InputDecoration(labelText: '帳號'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: passwordController,
              decoration: const InputDecoration(labelText: '密碼'),
              obscureText: true,
            ),
            const SizedBox(height: 10),
            TextField(
              controller: confirmController,
              decoration: const InputDecoration(labelText: '確認密碼'),
              obscureText: true,
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () async {
                final username = usernameController.text.trim();
                final password = passwordController.text;
                final confirm = confirmController.text;
                final name = nameController.text.trim();

                if (name.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('請輸入名稱')),
                  );
                  return;
                }

                if (username.isEmpty || password.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('請輸入帳號與密碼')),
                  );
                  return;
                }

                if (password != confirm) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('密碼不一致')),
                  );
                  return;
                }

                final validationMessage = await DatabaseHelper.instance.validateRegistration(
                  name: name,
                  username: username,
                  password: password,
                );

                if (validationMessage != null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(validationMessage)),
                  );
                  return;
                }

                // 新增使用者到資料庫
                await DatabaseHelper.instance.insertUser({
                  'userId': DateTime.now().millisecondsSinceEpoch.toString(),
                  'username': username,
                  'password': password,
                  'name': name,
                });

                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('註冊成功')),
                );

                Navigator.pop(context); // 返回登入頁
              },
              child: const Text('註冊'),
            ),
          ],
        ),
      ),
    );
  }
}
