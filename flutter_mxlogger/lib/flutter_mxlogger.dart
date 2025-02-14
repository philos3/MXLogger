library flutter_mxlogger;

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
export 'flutter_mxlogger.dart';

///日志文件存储策略
enum MXStoragePolicyType {
  yyyy_MM_dd,

  /// 按天存储 对应文件名: 2023-01-11_filename.mx
  yyyy_MM_dd_HH,

  /// 按小时存储 对应文件名: 2023-01-11-15_filename.mx
  yyyy_ww,

  /// 按周存储 对应文件名: 2023-01-02w_filename.mx（02w是指一年中的第2周）
  yyyy_MM

  /// 按月存储 对应文件名: 2023-01_filename.mx
}

class MXFileEntity {
  late String? name; /// 文件名
  late int size; /// 文件大小(byte)
  late int createTimeStamp; /// 文件创建时间
  late int lastTimeStamp; /// 文件最后修改时间

  DateTime get createTime  => DateTime.fromMillisecondsSinceEpoch(createTimeStamp*1000);

  DateTime get lastTime => DateTime.fromMillisecondsSinceEpoch(lastTimeStamp*1000);

  MXFileEntity(
      {this.name, this.size = 0, this.createTimeStamp = 0, this.lastTimeStamp = 0});
  @override
  String toString() {
   return "name:$name size:$size createTime:$createTime lastTime:$lastTime";
  }
}

typedef LoggerFunction = Void Function(
    Pointer<Int8>, Pointer<Int8>, Pointer<Int8>);

typedef FlutterLogFunction = void Function(
    Pointer<Int8>, Pointer<Int8>, Pointer<Int8>);

class MXLogger with WidgetsBindingObserver {
  Pointer<Void> _handle = nullptr;

  static const MethodChannel _channel = MethodChannel('flutter_mxlogger');


  bool get enable => _enable;


  /// 获取日志文件夹的磁盘路径(directory+nameSpace)
  String get diskcachePath => getDiskcachePath();

  /// 获取日志底层的唯一标识 可以通过这个key操作日志对象
  /// 业务场景: 如果是一个大型的app 你的app可能会模块化(组件化)
  /// 但是你希望所有子模块(子组件)使用在主工程初始化的log，
  /// 这个时候为了方便解耦业务你不需要传logger对象 只需要传入这个key，然后通过logLoggerKey 进行日志写入
  String? get loggerKey => getLoggerKey();
  /// 获取存储的日志大小 (byte)
  int get logSize => getLogSize();
  /// 获取日志文件列表
  List<MXFileEntity> get logFiles => getLogFiles();

  String? get cryptKey => _cryptKey;

  String? get iv => _iv;


  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused &&
        _shouldRemoveExpiredDataWhenEnterBackground == true) {
      removeExpireData();
    }
  }

  /// 使用自定义路径初始化MXLogger
  /// nameSpace: 日志文件的命名空间建议使用域名反转保证唯一性
  /// directory: 自定义日志文件路径
  /// storagePolicy: 日志文件存储策略
  /// fileName: 自定义文件名
  /// fileHeader:日志文件头信息，业务可以在初始化mxlogger的时候 写入一些业务相关的信息 比如app版本 所属平台等等 文件创建的时候这条数据会被写入
  /// cryptKey:  如果日志信息需要加密需要填入这个值 应为正好为16个英文字母
  /// iv: 如果不填默认和cryptKey一致
  MXLogger(
      {required String nameSpace,
      required String directory,
      MXStoragePolicyType storagePolicy = MXStoragePolicyType.yyyy_MM_dd,
      String? fileName,
      String? fileHeader,
      String? cryptKey,
      String? iv}) {
    _cryptKey = cryptKey;
    _iv = iv;
    WidgetsBinding.instance.addObserver(this);

    Pointer<Utf8> nsPtr = nameSpace.toNativeUtf8();
    Pointer<Utf8> drPtr = directory.toNativeUtf8();

    String policy =
        storagePolicy.toString().replaceAll("MXStoragePolicyType.", "");

    Pointer<Utf8> storagePolicyPtr = policy.toNativeUtf8();
    Pointer<Utf8> fileNamePtr =
        fileName == null ? nullptr : fileName.toNativeUtf8();
    Pointer<Utf8> fileHeaderPtr =
        fileHeader == null ? nullptr : fileHeader.toNativeUtf8();

    Pointer<Utf8> cryptKeyPtr =
        cryptKey == null ? nullptr : cryptKey.toNativeUtf8();

    Pointer<Utf8> ivPtr = iv == null ? nullptr : iv.toNativeUtf8();

    _handle = _initialize(nsPtr, drPtr, storagePolicyPtr, fileNamePtr,
        fileHeaderPtr, cryptKeyPtr, ivPtr);

    calloc.free(nsPtr);
    calloc.free(drPtr);
    if (storagePolicyPtr != nullptr) {
      calloc.free(storagePolicyPtr);
    }
    if (fileNamePtr != nullptr) {
      calloc.free(fileNamePtr);
    }
    if (fileHeaderPtr != nullptr) {
      calloc.free(fileHeaderPtr);
    }
    if (cryptKeyPtr != nullptr) {
      calloc.free(cryptKeyPtr);
    }
    if (ivPtr != nullptr) {
      calloc.free(ivPtr);
    }
  }

  /// 初始化MXLogger
  /// nameSpace: 日志文件的命名空间建议使用域名反转保证唯一性
  /// directory: 自定义日志文件路径
  /// storagePolicy: 日志文件存储策略
  /// 默认路径 ios:/Library/com.mxlog.LoggerCache/nameSpace
  ///         android: /files/com.mxlog.LoggerCache/nameSpace
  /// fileName: 自定义文件名 默认值 log
  /// fileHeader:日志文件头信息，业务可以在初始化mxlogger的时候 写入一些业务相关的信息 比如app版本 所属平台等等 文件创建的时候这条数据会被写入
  /// cryptKey:  如果日志信息需要加密需要填入这个值 应为正好为16个英文字母
  /// iv: 如果不填默认和cryptKey一致
  static Future<MXLogger> initialize(
      {required String nameSpace,
      String? directory,
      MXStoragePolicyType storagePolicy = MXStoragePolicyType.yyyy_MM_dd,
      String? fileName,
      String? fileHeader,
      String? cryptKey,
      String? iv}) async {
    String ns = nameSpace;
    String dr = directory ?? "";

    Map<dynamic, dynamic> result = await _channel.invokeMethod(
        "initialize", {"nameSpace": nameSpace, "directory": directory});
    dr = result["directory"];

    MXLogger mxLogger = MXLogger(
        nameSpace: ns,
        directory: dr,
        storagePolicy: storagePolicy,
        fileName: fileName,
        fileHeader: fileHeader,
        cryptKey: cryptKey,
        iv: iv);

    return mxLogger;
  }

  /// 释放log
  static void destroy({required String nameSpace, String? directory}) {
    Pointer<Utf8> nsPtr = nameSpace.toNativeUtf8();
    Pointer<Utf8> drPtr =
        directory == null ? nullptr : directory.toNativeUtf8();
    _destroy(nsPtr, drPtr);
    calloc.free(nsPtr);
    calloc.free(drPtr);
  }

  /// 通过key 释放log对象
  static void destroyWithLoggerKey(String loggerKey) {
    Pointer<Utf8> keyPtr = loggerKey.toNativeUtf8();
    _destroyWithLoggerKey(keyPtr);
    calloc.free(keyPtr);
  }

  /// 类方法 使用 mapKey操作日志
  static void logLoggerKey(String? loggerKey, int lvl, String msg,
      {String? name, String? tag}) {
    Pointer<Utf8> loggerKeyPtr =
        loggerKey != null ? loggerKey.toNativeUtf8() : nullptr;

    Pointer<Utf8> namePtr = name != null ? name.toNativeUtf8() : nullptr;
    Pointer<Utf8> tagPtr = tag != null ? tag.toNativeUtf8() : nullptr;
    Pointer<Utf8> msgPtr = msg.toNativeUtf8();

    _log_loggerKey(loggerKeyPtr, namePtr, lvl, msgPtr, tagPtr);

    calloc.free(loggerKeyPtr);
    calloc.free(namePtr);
    calloc.free(tagPtr);
    calloc.free(msgPtr);
  }

  /// 类方法 方便调用
  static void debugLog(String? loggerKey, String msg,
      {String? name, String? tag}) {
    logLoggerKey(loggerKey, 0, msg, name: name, tag: tag);
  }

  static void infoLog(String? loggerKey, String msg,
      {String? name, String? tag}) {
    logLoggerKey(loggerKey, 1, msg, name: name, tag: tag);
  }

  static void warnLog(String? loggerKey, String msg,
      {String? name, String? tag}) {
    logLoggerKey(loggerKey, 2, msg, name: name, tag: tag);
  }

  static void errorLog(String? loggerKey, String msg,
      {String? name, String? tag}) {
    logLoggerKey(loggerKey, 3, msg, name: name, tag: tag);
  }

  static void fatalLog(String? loggerKey, String msg,
      {String? name, String? tag}) {
    logLoggerKey(loggerKey, 4, msg, name: name, tag: tag);
  }

  /// 程序进入后台的时候是否去清理过期文件 默认为YES
  void shouldRemoveExpiredDataWhenEnterBackground(bool should) {
    _shouldRemoveExpiredDataWhenEnterBackground = should;
  }

  /// 设置写入日志文件等级
  ///    0:debug
  ///     1:info
  ///     2:warn
  ///     3:error
  ///     4:fatal
  void setFileLevel(int lvl) {
    if (enable == false) return;
    _setFileLevel(_handle, lvl);
  }

  /// 设置是否禁用日志写入功能
  void setEnable(bool enable) {
    _enable = enable;
    _setEnable(_handle, enable == true ? 1 : 0);
  }

  /// 设置是否禁用控制台输出功能
  void setConsoleEnable(bool e) {
    if (enable == false) return;
    _setConsoleEnable(_handle, e == true ? 1 : 0);
  }

  /// 设置日志文件存储最大时长(s) 默认为0 不限制   60 * 60 *24 *7； 即一个星期
  void setMaxDiskAge(int age) {
    if (enable == false) return;
    _setMaxdiskAge(_handle, age);
  }

  /// 设置日志文件存储最大字节数(byte) 默认为0 不限制 1024 * 1024 * 10; 即10M
  void setMaxDiskSize(int size) {
    if (enable == false) return;
    _setMaxdiskSize(_handle, size);
  }

  /// 删除过期文件
  void removeExpireData() {
    if (enable == false) return;
    _removeExpireData(_handle);
  }
  /// 删除除当前正在写入的所有日志文件
  void removeBeforeAllData(){
    if (enable == false) return;
    _removeBeforeAllData(_handle);
  }

  /// 删除所有日志文件
  void removeAll() {
    if (enable == false) return;
    _removeAll(_handle);
  }

  /// 获取存储的日志大小 (byte)
  int getLogSize() {
    if (enable == false) return 0;
    return _getLogSize(_handle);
  }

  /// 获取日志文件夹的存储路径
  String getDiskcachePath() {
    if (enable == false) return "";
    Pointer<Int8> result = _getDiskcachePath(_handle);

    String path = result.cast<Utf8>().toDartString();
    return path;
  }

  /// 获取日志底层的唯一标识 可以通过这个key操作日志对象
  /// 业务场景: 如果是一个大型的app 你的app可能会模块化(组件化)
  /// 但是你希望所有子模块(子组件)使用在主工程初始化的log，
  /// 这个时候为了方便解耦业务你不需要传logger对象 只需要传入这个key，然后通过logLoggerKey 进行日志写入
  String? getLoggerKey() {
    Pointer<Int8> result = _getLoggerKey(_handle);
    Pointer<Utf8> mapPoint = result.cast<Utf8>();
    if (mapPoint != nullptr) {
      String loggerKey = mapPoint.toDartString();
      return loggerKey;
    }
    return null;
  }

  void debug(String msg, {String? name, String? tag}) {
    log(0, msg, name: name, tag: tag);
  }

  void info(String msg, {String? name, String? tag}) {
    log(1, msg, name: name, tag: tag);
  }

  void warn(String msg, {String? name, String? tag}) {
    log(2, msg, name: name, tag: tag);
  }

  void error(String msg, {String? name, String? tag}) {
    log(3, msg, name: name, tag: tag);
  }

  void fatal(String msg, {String? name, String? tag}) {
    log(4, msg, name: name, tag: tag);
  }

  void log(int lvl, String msg, {String? name, String? tag}) {
    if (enable == false) return;

    Pointer<Utf8> namePtr = name != null ? name.toNativeUtf8() : nullptr;
    Pointer<Utf8> tagPtr = tag != null ? tag.toNativeUtf8() : nullptr;
    Pointer<Utf8> msgPtr = msg.toNativeUtf8();

    _log(_handle, namePtr, lvl, msgPtr, tagPtr);

    calloc.free(namePtr);
    calloc.free(tagPtr);
    calloc.free(msgPtr);
  }


  List<MXFileEntity> getLogFiles() {
    final arrayPtr = calloc<Pointer<Pointer<Pointer<Utf8>>>>();
    final sizeArrayPtr = calloc<Pointer<Pointer<Uint32>>>();
    final count = _getLogfiles(_handle, arrayPtr, sizeArrayPtr);
    List<MXFileEntity> _mxFileList = [];
    if (count > 0) {
      final array_array = arrayPtr[0];
      final sizeArray_array = sizeArrayPtr[0];
      for (int i = 0; i < count; i++) {
        final charArray = array_array[i];

        final sizeArray = sizeArray_array[i];

        final point_name = charArray[0];
        final point_size = charArray[1];
        final point_last_timestamp = charArray[2];
        final point_create_timestamp = charArray[3];

        final point_name_size = sizeArray[0];
        final point_size_size = sizeArray[1];
        final point_last_timestamp_size = sizeArray[2];
        final point_create_timestamp_size = sizeArray[3];

        String? name = _buffer2String(point_name.cast(), point_name_size);
        String? size = _buffer2String(point_size.cast(), point_size_size);
        String? last_timestamp = _buffer2String(
            point_last_timestamp.cast(), point_last_timestamp_size);

        String? create_timestamp = _buffer2String(
            point_create_timestamp.cast(), point_create_timestamp_size);

        MXFileEntity entity =  MXFileEntity(
            name: name,
            size: int.parse(size ?? "0"),
            createTimeStamp: int.parse(create_timestamp ?? "0"),
            lastTimeStamp: int.parse(last_timestamp ?? "0"));
        _mxFileList.add(entity);

        calloc.free(charArray[0]);
        calloc.free(charArray[1]);
        calloc.free(charArray[2]);
        calloc.free(charArray[3]);

        calloc.free(charArray);
        calloc.free(sizeArray);

      }
      calloc.free(array_array);
      calloc.free(sizeArray_array);

    }

    calloc.free(arrayPtr);
    calloc.free(sizeArrayPtr);
    return _mxFileList;
  }

  /// 目前只对 ios端生效
  static List<Map<String, dynamic>> selectLogfiles(
      {required String directory}) {
    if (Platform.isIOS == false) return [];

    List<Map<String, dynamic>> logFiles = [];

    Pointer<Utf8> dirPtr = directory.toNativeUtf8();
    final arrayPtr = calloc<Pointer<Pointer<Utf8>>>();
    final sizeArrayPtr = calloc<Pointer<Uint32>>();
    final count = _select_logfiles(dirPtr, arrayPtr, sizeArrayPtr);
    if (count > 0) {
      final array = arrayPtr[0];
      final sizeArray = sizeArrayPtr[0];

      for (int i = 0; i < count; i++) {
        final keyPtr = array[i];
        final size = sizeArray[i];
        String? logInfo = _buffer2String(keyPtr.cast(), size);
        if (logInfo != null) {
          List<String> _list = logInfo.split(",");
          Map<String, dynamic> _map = {
            "name": _list[0],
            "size": int.parse(_list[1]),
            "timestamp": int.parse(_list[2])
          };
          logFiles.add(_map);
        }
      }

      calloc.free(array);
      calloc.free(sizeArray);
    }

    calloc.free(dirPtr);
    calloc.free(arrayPtr);
    calloc.free(sizeArrayPtr);

    return logFiles;
  }

  static String? _buffer2String(Pointer<Uint8>? ptr, int length) {
    if (ptr != null && ptr != nullptr) {
      var listView = ptr.asTypedList(length);
      return const Utf8Decoder().convert(listView);
    }
    return null;
  }


  String? _cryptKey;
  String? _iv;
  bool _enable = true;
  bool _shouldRemoveExpiredDataWhenEnterBackground = true;

}

final DynamicLibrary _nativeLib = Platform.isAndroid
    ? DynamicLibrary.open("libmxlogger.so")
    : DynamicLibrary.process();

String _mxlogger_function(String funcName) {
  return "flutter_mxlogger_" + funcName;
}

///初始化logger
final Pointer<Void> Function(Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>,
        Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>)
    _initialize = _nativeLib
        .lookup<
            NativeFunction<
                Pointer<Void> Function(
                    Pointer<Utf8>,
                    Pointer<Utf8>,
                    Pointer<Utf8>,
                    Pointer<Utf8>,
                    Pointer<Utf8>,
                    Pointer<Utf8>,
                    Pointer<Utf8>)>>(_mxlogger_function("initialize"))
        .asFunction();

final Pointer<Void> Function(Pointer<Utf8>, Pointer<Utf8>) _destroy = _nativeLib
    .lookup<
        NativeFunction<
            Pointer<Void> Function(
                Pointer<Utf8>, Pointer<Utf8>)>>(_mxlogger_function("destroy"))
    .asFunction();

final Pointer<Void> Function(Pointer<Utf8>) _destroyWithLoggerKey = _nativeLib
    .lookup<NativeFunction<Pointer<Void> Function(Pointer<Utf8>)>>(
        _mxlogger_function("destroyWithLoggerKey"))
    .asFunction();

final void Function(
        Pointer<Void>, Pointer<Utf8>, int, Pointer<Utf8>, Pointer<Utf8>) _log =
    _nativeLib
        .lookup<
            NativeFunction<
                Void Function(Pointer<Void>, Pointer<Utf8>, Int32,
                    Pointer<Utf8>, Pointer<Utf8>)>>(_mxlogger_function("log"))
        .asFunction();

final void Function(
        Pointer<Utf8>, Pointer<Utf8>, int, Pointer<Utf8>, Pointer<Utf8>)
    _log_loggerKey = _nativeLib
        .lookup<
            NativeFunction<
                Void Function(
                    Pointer<Utf8>,
                    Pointer<Utf8>,
                    Int32,
                    Pointer<Utf8>,
                    Pointer<Utf8>)>>(_mxlogger_function("log_loggerKey"))
        .asFunction();

final void Function(Pointer<Void>, int) _setFileLevel = _nativeLib
    .lookup<NativeFunction<Void Function(Pointer<Void>, Int32)>>(
        _mxlogger_function("set_file_level"))
    .asFunction();

final void Function(Pointer<Void>, int) _setEnable = _nativeLib
    .lookup<NativeFunction<Void Function(Pointer<Void>, Int32)>>(
        _mxlogger_function("set_enable"))
    .asFunction();

final void Function(Pointer<Void>, int) _setConsoleEnable = _nativeLib
    .lookup<NativeFunction<Void Function(Pointer<Void>, Int32)>>(
        _mxlogger_function("set_console_enable"))
    .asFunction();

final Pointer<Int8> Function(Pointer<Void>) _getDiskcachePath = _nativeLib
    .lookup<NativeFunction<Pointer<Int8> Function(Pointer<Void>)>>(
        _mxlogger_function("get_diskcache_path"))
    .asFunction();
final Pointer<Int8> Function(Pointer<Void>) _getLoggerKey = _nativeLib
    .lookup<NativeFunction<Pointer<Int8> Function(Pointer<Void>)>>(
        _mxlogger_function("get_loggerKey"))
    .asFunction();

final void Function(Pointer<Void>, int) _setMaxdiskAge = _nativeLib
    .lookup<NativeFunction<Void Function(Pointer<Void>, Int32)>>(
        _mxlogger_function("set_max_disk_age"))
    .asFunction();

final void Function(Pointer<Void>, int) _setMaxdiskSize = _nativeLib
    .lookup<NativeFunction<Void Function(Pointer<Void>, Uint64)>>(
        _mxlogger_function("set_max_disk_size"))
    .asFunction();

final void Function(Pointer<Void>) _removeExpireData = _nativeLib
    .lookup<NativeFunction<Void Function(Pointer<Void>)>>(
        _mxlogger_function("remove_expire_data"))
    .asFunction();

final void Function(Pointer<Void>) _removeBeforeAllData = _nativeLib
    .lookup<NativeFunction<Void Function(Pointer<Void>)>>(
    _mxlogger_function("remove_before_all_data"))
    .asFunction();

final int Function(Pointer<Void>, Pointer<Pointer<Pointer<Pointer<Utf8>>>>,
        Pointer<Pointer<Pointer<Uint32>>>) _getLogfiles =
    _nativeLib
        .lookup<
                NativeFunction<
                    Uint64 Function(
                        Pointer<Void>,
                        Pointer<Pointer<Pointer<Pointer<Utf8>>>>,
                        Pointer<Pointer<Pointer<Uint32>>>)>>(
            _mxlogger_function("get_logfiles"))
        .asFunction();

final int Function(Pointer<Utf8>, Pointer<Pointer<Pointer<Utf8>>>,
        Pointer<Pointer<Uint32>>) _select_logfiles =
    _nativeLib
        .lookup<
                NativeFunction<
                    Uint64 Function(
                        Pointer<Utf8>,
                        Pointer<Pointer<Pointer<Utf8>>>,
                        Pointer<Pointer<Uint32>>)>>(
            _mxlogger_function("select_logfiles"))
        .asFunction();

final int Function(Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>, Pointer<Int32>,
        Pointer<Pointer<Pointer<Utf8>>>, Pointer<Pointer<Uint32>>)
    _select_logmsg = _nativeLib
        .lookup<
                NativeFunction<
                    Uint64 Function(
                        Pointer<Utf8>,
                        Pointer<Utf8>,
                        Pointer<Utf8>,
                        Pointer<Int32>,
                        Pointer<Pointer<Pointer<Utf8>>>,
                        Pointer<Pointer<Uint32>>)>>(
            _mxlogger_function("select_logmsg"))
        .asFunction();

final void Function(Pointer<Void>) _removeAll = _nativeLib
    .lookup<NativeFunction<Void Function(Pointer<Void>)>>(
        _mxlogger_function("remove_all"))
    .asFunction();

final int Function(Pointer<Void>) _getLogSize = _nativeLib
    .lookup<NativeFunction<Uint64 Function(Pointer<Void>)>>(
        _mxlogger_function("get_log_size"))
    .asFunction();
