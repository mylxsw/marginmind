import 'dart:io';

bool isNativeNetworkError(Object error) => error is TlsException || error is SocketException || error is HttpException;
