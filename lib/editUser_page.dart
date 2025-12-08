import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../database/database_helper.dart';

class EditUserPage extends StatefulWidget {
  final String userId;
  const EditUserPage({super.key, required this.userId});

  @override
  State<EditUserPage> createState() => _EditUserPageState();
}

class _EditUserPageState extends State<EditUserPage> {
  final _formKey = GlobalKey<FormState>();

  String username = '';
  String name = '';
  String password = '';
  File? avatarFile;
  bool loading = true;

  final TextEditingController _nameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  Future<void> _loadUser() async {
    final user = await DatabaseHelper.instance.getUserById(widget.userId);
    if (user != null) {
      final avatarPath = '${Directory.current.path}\\database\\avatars\\${widget.userId}.png';
      setState(() {
        username = user['username'];
        name = user['name'];
        password = user['password'];
        avatarFile = File(avatarPath);
        _nameController.text = name;
        loading = false;
      });
    }
  }

  Future<void> _pickAvatar() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.image);
    if (result != null && result.files.single.path != null) {
      final pickedFile = File(result.files.single.path!);
      final appDir = Directory('${Directory.current.path}\\database\\avatars');
      if (!await appDir.exists()) await appDir.create(recursive: true);

      final newPath = '${appDir.path}\\${widget.userId}.png';
      await pickedFile.copy(newPath);

      setState(() {
        avatarFile = File(newPath);
      });
    }
  }

  // 彈出舊密碼視窗
  Future<bool> _verifyOldPassword() async {
    final controller = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('輸入舊密碼'),
        content: TextField(
          controller: controller,
          obscureText: true,
          decoration: const InputDecoration(hintText: '舊密碼'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          TextButton(
            onPressed: () {
              if (controller.text == password) {
                Navigator.pop(context, true);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('舊密碼錯誤')),
                );
              }
            },
            child: const Text('確認'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  // 彈出新密碼視窗
  Future<void> _updatePassword() async {
    final newPassController = TextEditingController();
    final confirmPassController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('更新密碼'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: newPassController,
              obscureText: true,
              decoration: const InputDecoration(hintText: '新密碼'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: confirmPassController,
              obscureText: true,
              decoration: const InputDecoration(hintText: '確認新密碼'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          TextButton(
            onPressed: () {
              if (newPassController.text.isEmpty || confirmPassController.text.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('新密碼不可為空')),
                );
                return;
              }
              if (newPassController.text != confirmPassController.text) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('新密碼兩次輸入不一致')),
                );
                return;
              }
              Navigator.pop(context, true);
            },
            child: const Text('更新'),
          ),
        ],
      ),
    );

    if (result == true) {
      final newPassword = newPassController.text;

      // 檢查密碼是否已被使用
      final allUsers = await DatabaseHelper.instance.getAllUsers();
      for (var user in allUsers) {
        if (user['userId'] != widget.userId && user['password'] == newPassword) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('密碼已被使用')),
          );
          return;
        }
      }

      // 更新密碼
      final updateResult = await DatabaseHelper.instance.updateUser(widget.userId, {
        'username': username,
        'name': name,
        'password': newPassword,
      });

      if (updateResult == 'success') {
        setState(() {
          password = newPassword;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('密碼更新成功！')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(updateResult)),
        );
      }
    }
  }

  // 儲存名稱
  Future<void> _saveName() async {
    final newName = _nameController.text.trim();
    if (newName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('名稱不可為空')),
      );
      return;
    }

    // 檢查名稱是否重複
    final allUsers = await DatabaseHelper.instance.getAllUsers();
    for (var user in allUsers) {
      if (user['userId'] != widget.userId && user['name'] == newName) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('名稱已存在')),
        );
        return;
      }
    }

    final result = await DatabaseHelper.instance.updateUser(widget.userId, {
      'username': username,
      'name': newName,
      'password': password,
    });

    if (result == 'success') {
      setState(() {
        name = newName;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('名稱更新成功！')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());

    return Scaffold(
      appBar: AppBar(title: const Text('編輯使用者資料')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ListView(
          children: [
            Center(
              child: GestureDetector(
                onTap: _pickAvatar,
                child: CircleAvatar(
                  radius: 50,
                  backgroundColor: Colors.teal.shade100,
                  backgroundImage: (avatarFile != null && avatarFile!.existsSync())
                      ? FileImage(avatarFile!)
                      : null,
                  child: (avatarFile == null || !avatarFile!.existsSync())
                      ? const Icon(Icons.person, size: 50, color: Colors.teal)
                      : null,
                ),
              ),
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: '名稱'),
            ),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: _saveName,
              child: const Text('儲存'),
            ),
            const SizedBox(height: 10),
            TextFormField(
              initialValue: username,
              decoration: const InputDecoration(labelText: '帳號'),
              enabled: false, // 帳號不可編輯
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    initialValue: '*****',
                    decoration: const InputDecoration(labelText: '密碼'),
                    enabled: false, // 密碼不可直接編輯
                  ),
                ),
                const SizedBox(width: 10),
                ElevatedButton(
                  onPressed: () async {
                    final verified = await _verifyOldPassword();
                    if (verified) {
                      await _updatePassword();
                    }
                  },
                  child: const Text('編輯密碼'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
