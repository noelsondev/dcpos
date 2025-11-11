// lib/utils/snackbar_utils.dart

import 'package:flutter/material.dart';
import 'package:dio/dio.dart';

class SnackbarUtils {
  // 💡 NUEVA FUNCIÓN: Solo obtiene y formatea el String del error
  static String getErrorMessage(dynamic error) {
    String displayMessage = 'Error inesperado.';

    if (error is Exception) {
      displayMessage = error.toString().replaceFirst('Exception: ', '');
    } else if (error is DioException) {
      final responseData = error.response?.data;
      if (responseData != null &&
          responseData is Map &&
          (responseData.containsKey('detail') ||
              responseData.containsKey('message'))) {
        final detail = responseData['detail'] ?? responseData['message'];
        displayMessage = detail is String
            ? detail
            : 'Error en el servidor: ${detail.toString()}';
      } else if (error.response?.statusCode != null) {
        displayMessage =
            'Error ${error.response!.statusCode}: La solicitud falló.';
      } else {
        displayMessage =
            'Error de conexión. Verifica tu red o el estado del servidor.';
      }
    } else if (error.toString().contains(
      "type 'Null' is not a subtype of type",
    )) {
      displayMessage = 'Fallo de datos: El servidor envió datos incompletos.';
    } else {
      displayMessage =
          'Fallo de servicio: ${error.toString().split(':').last.trim()}';
    }
    return displayMessage;
  }

  // 💡 FUNCIÓN MODIFICADA: Ahora usa getErrorMessage()
  static void showSuccess(BuildContext context, String message) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  // 💡 FUNCIÓN MODIFICADA: Ahora usa getErrorMessage()
  static void showError(BuildContext context, dynamic error) {
    final displayMessage = getErrorMessage(error); // Obtener el string

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(displayMessage),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 5),
      ),
    );
  }
}
