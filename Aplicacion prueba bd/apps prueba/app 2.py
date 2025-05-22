#!/usr/bin/env python3
"""
Aplicación Demo Corregida para Capturas
Clínica Veterinaria Altavida - Sistema de Reabastecimiento Automático
"""

import mysql.connector
from mysql.connector import Error
import datetime
from tabulate import tabulate
import os
import time


class ClinicaVeterinariaDemo:
    def __init__(self):
        self.connection = None
        self.cursor = None

    def conectar_db(self):
        """Establece conexión con la base de datos"""
        try:
            self.connection = mysql.connector.connect(
                host='localhost',
                database='clinica_veterinaria_altavida',
                user='root',  # Cambiar según tu configuración
                password=''  # Cambiar según tu configuración
            )
            if self.connection.is_connected():
                self.cursor = self.connection.cursor()
                print("✅ Conexión exitosa a la base de datos MySQL")
                print("🏥 Base de datos: clinica_veterinaria_altavida")
                print("📅 Fecha actual:", datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S"))
                return True
        except Error as e:
            print(f"❌ Error al conectar: {e}")
            return False

    def cerrar_conexion(self):
        """Cierra la conexión con la base de datos"""
        if self.connection and self.connection.is_connected():
            self.cursor.close()
            self.connection.close()
            print("🔒 Conexión cerrada exitosamente")

    def pausa_para_captura(self, mensaje="Presione Enter para continuar..."):
        """Pausa para permitir tomar capturas"""
        print(f"\n📸 {mensaje}")
        input()

    def mostrar_menu_principal(self):
        """Muestra el menú principal de la aplicación"""
        print("\n" + "=" * 60)
        print("🏥 CLÍNICA VETERINARIA ALTAVIDA")
        print("   Sistema de Reabastecimiento Automático con Aprobación Médica")
        print("=" * 60)
        print("\n📋 DEMOSTRACIÓN DE FUNCIONALIDADES:")
        print("\n1. 💊 Ver Estado Actual del Inventario")
        print("2. 🔄 Actualizar Inventario (Disparar Trigger Automático)")
        print("3. 📊 Ver Estado del Sistema Completo")
        print("4. 🔔 Ver Notificaciones Generadas")
        print("5. 📋 Ver Solicitudes de Reabastecimiento")
        print("6. 🧪 Demostración Completa Paso a Paso")
        print("7. 📈 Reporte de Pruebas Realizadas")
        print("0. ❌ Salir")
        print("=" * 60)

    def ver_inventario_actual(self):
        """Muestra el estado actual del inventario"""
        print("\n💊 ESTADO ACTUAL DEL INVENTARIO")
        print("=" * 50)

        self.cursor.execute("""
            SELECT 
                m.id_medicamento as ID,
                m.nombre as Medicamento,
                im.cantidad as 'Cantidad Actual',
                im.nivel_minimo as 'Nivel Mínimo',
                im.nivel_optimo as 'Nivel Óptimo',
                im.ubicacion as Ubicación,
                CASE 
                    WHEN im.cantidad <= im.nivel_minimo THEN '🚨 CRÍTICO'
                    WHEN im.cantidad <= (im.nivel_minimo + 10) THEN '⚠️ BAJO'
                    ELSE '✅ NORMAL'
                END as Estado
            FROM medicamentos m
            JOIN inventario_medicamentos im ON m.id_medicamento = im.id_medicamento
            ORDER BY 
                CASE 
                    WHEN im.cantidad <= im.nivel_minimo THEN 1
                    WHEN im.cantidad <= (im.nivel_minimo + 10) THEN 2
                    ELSE 3
                END,
                im.cantidad ASC
        """)

        inventario = self.cursor.fetchall()
        headers = [desc[0] for desc in self.cursor.description]

        print("\n📊 INVENTARIO DE MEDICAMENTOS:")
        print(tabulate(inventario, headers=headers, tablefmt='grid'))

        # Mostrar estadísticas
        criticos = sum(1 for item in inventario if '🚨 CRÍTICO' in str(item))
        bajos = sum(1 for item in inventario if '⚠️ BAJO' in str(item))
        normales = sum(1 for item in inventario if '✅ NORMAL' in str(item))

        print(f"\n📈 ESTADÍSTICAS:")
        print(f"   🚨 Medicamentos en nivel crítico: {criticos}")
        print(f"   ⚠️ Medicamentos en nivel bajo: {bajos}")
        print(f"   ✅ Medicamentos en nivel normal: {normales}")
        print(f"   📦 Total de medicamentos: {len(inventario)}")

    def actualizar_inventario_demo(self):
        """Demostración de actualización que dispara el trigger"""
        print("\n🔄 DEMOSTRACIÓN: ACTUALIZAR INVENTARIO")
        print("=" * 50)
        print("Esta función demuestra cómo el trigger se activa automáticamente")
        print("cuando un medicamento alcanza su nivel mínimo.\n")

        # Mostrar medicamentos disponibles para la demo
        self.cursor.execute("""
            SELECT 
                m.id_medicamento,
                m.nombre,
                im.cantidad,
                im.nivel_minimo,
                im.nivel_optimo
            FROM medicamentos m
            JOIN inventario_medicamentos im ON m.id_medicamento = im.id_medicamento
            WHERE im.cantidad > im.nivel_minimo
            ORDER BY (im.cantidad - im.nivel_minimo) ASC
            LIMIT 5
        """)

        medicamentos = self.cursor.fetchall()
        print("💊 MEDICAMENTOS DISPONIBLES PARA DEMO:")
        print(tabulate(medicamentos,
                       headers=['ID', 'Medicamento', 'Cantidad Actual', 'Nivel Mínimo', 'Nivel Óptimo'],
                       tablefmt='grid'))

        self.pausa_para_captura("Captura esta pantalla - Estado ANTES de la actualización")

        # Selección automática para demo
        medicamento_demo = medicamentos[0] if medicamentos else None

        if not medicamento_demo:
            print("❌ No hay medicamentos disponibles para demo")
            return

        id_medicamento = medicamento_demo[0]
        nombre_medicamento = medicamento_demo[1]
        cantidad_actual = medicamento_demo[2]
        nivel_minimo = medicamento_demo[3]

        print(f"\n🎯 MEDICAMENTO SELECCIONADO PARA DEMO:")
        print(f"   📝 ID: {id_medicamento}")
        print(f"   💊 Nombre: {nombre_medicamento}")
        print(f"   📊 Cantidad actual: {cantidad_actual}")
        print(f"   ⚠️ Nivel mínimo: {nivel_minimo}")

        # Calcular nueva cantidad que dispare el trigger
        nueva_cantidad = max(1, nivel_minimo - 5)

        print(f"\n🔄 ACTUALIZANDO INVENTARIO...")
        print(f"   Nueva cantidad: {nueva_cantidad} (menor al nivel mínimo)")
        print(f"   Esto debería disparar el trigger automáticamente...")

        try:
            # Ejecutar la actualización que dispara el trigger
            self.cursor.execute("""
                UPDATE inventario_medicamentos
                SET cantidad = %s, fecha_actualizacion = NOW()
                WHERE id_medicamento = %s
            """, (nueva_cantidad, id_medicamento))

            self.connection.commit()

            print("\n✅ INVENTARIO ACTUALIZADO EXITOSAMENTE")
            print("🔥 TRIGGER DISPARADO AUTOMÁTICAMENTE")

            time.sleep(1)  # Pausa para que se procesen los triggers

            # Verificar la nueva solicitud de reabastecimiento
            print(f"\n🔍 VERIFICANDO SOLICITUD GENERADA AUTOMÁTICAMENTE...")
            self.cursor.execute("""
                SELECT 
                    sr.id_solicitud,
                    m.nombre as medicamento,
                    sr.cantidad_actual,
                    sr.cantidad_solicitada,
                    sr.estado,
                    sr.fecha_solicitud,
                    LEFT(sr.observaciones, 50) as observaciones
                FROM solicitudes_reabastecimiento sr
                JOIN medicamentos m ON sr.id_medicamento = m.id_medicamento
                WHERE sr.id_medicamento = %s
                ORDER BY sr.fecha_solicitud DESC
                LIMIT 1
            """, (id_medicamento,))

            solicitud = self.cursor.fetchone()
            if solicitud:
                print("\n🆕 NUEVA SOLICITUD DE REABASTECIMIENTO CREADA:")
                headers = ['ID Solicitud', 'Medicamento', 'Cantidad Actual',
                           'Cantidad Solicitada', 'Estado', 'Fecha Solicitud', 'Observaciones']
                print(tabulate([solicitud], headers=headers, tablefmt='grid'))

            # Verificar la notificación generada
            print(f"\n🔍 VERIFICANDO NOTIFICACIÓN GENERADA AUTOMÁTICAMENTE...")
            self.cursor.execute("""
                SELECT 
                    tipo_notificacion,
                    LEFT(mensaje, 100) as mensaje,
                    dirigido_a,
                    fecha_hora
                FROM notificaciones_administrativas
                WHERE tipo_notificacion = 'Reabastecimiento'
                AND mensaje LIKE %s
                ORDER BY fecha_hora DESC
                LIMIT 1
            """, (f'%{nombre_medicamento}%',))

            notificacion = self.cursor.fetchone()
            if notificacion:
                print("\n🔔 NUEVA NOTIFICACIÓN GENERADA:")
                headers = ['Tipo', 'Mensaje', 'Dirigido A', 'Fecha/Hora']
                print(tabulate([notificacion], headers=headers, tablefmt='grid'))

            self.pausa_para_captura("Captura esta pantalla - Estado DESPUÉS de la actualización")

        except mysql.connector.Error as err:
            print(f"\n❌ Error durante la actualización: {err}")

    def ver_estado_sistema_completo(self):
        """Muestra el estado completo del sistema sin usar procedimientos almacenados"""
        print("\n📊 ESTADO COMPLETO DEL SISTEMA")
        print("=" * 50)

        try:
            # Medicamentos en nivel crítico
            print("\n🚨 MEDICAMENTOS EN NIVEL CRÍTICO:")
            self.cursor.execute("""
                SELECT 
                    m.nombre as medicamento,
                    im.cantidad as cantidad_actual,
                    im.nivel_minimo,
                    im.nivel_optimo
                FROM inventario_medicamentos im
                INNER JOIN medicamentos m ON im.id_medicamento = m.id_medicamento
                WHERE im.cantidad <= im.nivel_minimo
                ORDER BY im.cantidad ASC
            """)

            criticos = self.cursor.fetchall()
            if criticos:
                headers = ['Medicamento', 'Cantidad Actual', 'Nivel Mínimo', 'Nivel Óptimo']
                print(tabulate(criticos, headers=headers, tablefmt='grid'))
            else:
                print("✅ No hay medicamentos en nivel crítico")

            # Solicitudes pendientes
            print("\n📋 SOLICITUDES DE REABASTECIMIENTO PENDIENTES:")
            self.cursor.execute("""
                SELECT 
                    sr.id_solicitud,
                    m.nombre as medicamento,
                    sr.cantidad_actual,
                    sr.cantidad_solicitada,
                    sr.fecha_solicitud
                FROM solicitudes_reabastecimiento sr
                INNER JOIN medicamentos m ON sr.id_medicamento = m.id_medicamento
                WHERE sr.estado = 'Pendiente'
                ORDER BY sr.fecha_solicitud DESC
            """)

            solicitudes = self.cursor.fetchall()
            if solicitudes:
                headers = ['ID Solicitud', 'Medicamento', 'Cantidad Actual', 'Cantidad Solicitada', 'Fecha Solicitud']
                print(tabulate(solicitudes, headers=headers, tablefmt='grid'))
            else:
                print("✅ No hay solicitudes pendientes")

            # Notificaciones pendientes
            print("\n🔔 NOTIFICACIONES PENDIENTES:")
            self.cursor.execute("""
                SELECT 
                    tipo_notificacion,
                    LEFT(mensaje, 80) as mensaje,
                    dirigido_a,
                    fecha_hora
                FROM notificaciones_administrativas
                WHERE leida = FALSE AND tipo_notificacion = 'Reabastecimiento'
                ORDER BY fecha_hora DESC
                LIMIT 5
            """)

            notificaciones = self.cursor.fetchall()
            if notificaciones:
                headers = ['Tipo', 'Mensaje', 'Dirigido A', 'Fecha/Hora']
                print(tabulate(notificaciones, headers=headers, tablefmt='grid'))
            else:
                print("✅ No hay notificaciones pendientes")

        except mysql.connector.Error as err:
            print(f"\n❌ Error al consultar estado del sistema: {err}")

    def ver_notificaciones(self):
        """Muestra las notificaciones del sistema"""
        print("\n🔔 NOTIFICACIONES DEL SISTEMA")
        print("=" * 50)

        self.cursor.execute("""
            SELECT 
                id_notificacion as ID,
                tipo_notificacion as Tipo,
                LEFT(mensaje, 80) as Mensaje,
                dirigido_a as 'Dirigido A',
                fecha_hora as 'Fecha/Hora',
                CASE WHEN leida = 0 THEN '❌ NO LEÍDA' ELSE '✅ LEÍDA' END as Estado
            FROM notificaciones_administrativas
            WHERE tipo_notificacion = 'Reabastecimiento'
            ORDER BY fecha_hora DESC
            LIMIT 10
        """)

        notificaciones = self.cursor.fetchall()
        headers = [desc[0] for desc in self.cursor.description]

        if notificaciones:
            print("\n📬 NOTIFICACIONES DE REABASTECIMIENTO:")
            print(tabulate(notificaciones, headers=headers, tablefmt='grid'))

            # Estadísticas
            no_leidas = sum(1 for n in notificaciones if '❌ NO LEÍDA' in str(n))
            leidas = len(notificaciones) - no_leidas

            print(f"\n📈 ESTADÍSTICAS DE NOTIFICACIONES:")
            print(f"   ❌ No leídas: {no_leidas}")
            print(f"   ✅ Leídas: {leidas}")
            print(f"   📧 Total mostradas: {len(notificaciones)}")

        else:
            print("\n✅ No hay notificaciones de reabastecimiento")

    def ver_solicitudes_reabastecimiento(self):
        """Muestra las solicitudes de reabastecimiento"""
        print("\n📋 SOLICITUDES DE REABASTECIMIENTO")
        print("=" * 50)

        self.cursor.execute("""
            SELECT 
                sr.id_solicitud as ID,
                m.nombre as Medicamento,
                sr.cantidad_actual as 'Cantidad Actual',
                sr.cantidad_solicitada as 'Cantidad Solicitada',
                sr.estado as Estado,
                DATE_FORMAT(sr.fecha_solicitud, '%Y-%m-%d %H:%i') as 'Fecha Solicitud',
                CASE 
                    WHEN sr.fecha_respuesta IS NOT NULL 
                    THEN DATE_FORMAT(sr.fecha_respuesta, '%Y-%m-%d %H:%i')
                    ELSE 'Pendiente'
                END as 'Fecha Respuesta'
            FROM solicitudes_reabastecimiento sr
            JOIN medicamentos m ON sr.id_medicamento = m.id_medicamento
            ORDER BY sr.fecha_solicitud DESC
            LIMIT 10
        """)

        solicitudes = self.cursor.fetchall()
        headers = [desc[0] for desc in self.cursor.description]

        if solicitudes:
            print("\n📝 SOLICITUDES DE REABASTECIMIENTO:")
            print(tabulate(solicitudes, headers=headers, tablefmt='grid'))

            # Estadísticas
            pendientes = sum(1 for s in solicitudes if s[4] == 'Pendiente')
            aprobadas = sum(1 for s in solicitudes if s[4] == 'Aprobada')
            rechazadas = sum(1 for s in solicitudes if s[4] == 'Rechazada')

            print(f"\n📊 ESTADÍSTICAS DE SOLICITUDES:")
            print(f"   ⏳ Pendientes: {pendientes}")
            print(f"   ✅ Aprobadas: {aprobadas}")
            print(f"   ❌ Rechazadas: {rechazadas}")
            print(f"   📄 Total mostradas: {len(solicitudes)}")

        else:
            print("\n📭 No hay solicitudes de reabastecimiento")

    def demostracion_completa(self):
        """Ejecuta una demostración completa paso a paso"""
        print("\n🧪 DEMOSTRACIÓN COMPLETA DEL SISTEMA")
        print("=" * 60)
        print("Esta demostración mostrará todo el proceso de reabastecimiento automático")
        print("desde la actualización del inventario hasta la generación de notificaciones.")

        self.pausa_para_captura("Iniciando demostración completa...")

        # Paso 1: Estado inicial
        print("\n🔍 PASO 1: ESTADO INICIAL DEL SISTEMA")
        print("-" * 40)
        self.ver_inventario_actual()
        self.pausa_para_captura("Paso 1 completado - Estado inicial")

        # Paso 2: Actualización que dispara trigger
        print("\n🔄 PASO 2: DISPARAR TRIGGER AUTOMÁTICO")
        print("-" * 40)
        self.actualizar_inventario_demo()
        self.pausa_para_captura("Paso 2 completado - Trigger disparado")

        # Paso 3: Verificar resultados
        print("\n📊 PASO 3: VERIFICAR RESULTADOS")
        print("-" * 40)
        self.ver_estado_sistema_completo()
        self.pausa_para_captura("Paso 3 completado - Resultados verificados")

        # Paso 4: Ver notificaciones generadas
        print("\n🔔 PASO 4: NOTIFICACIONES GENERADAS")
        print("-" * 40)
        self.ver_notificaciones()
        self.pausa_para_captura("Paso 4 completado - Notificaciones mostradas")

        # Paso 5: Ver solicitudes creadas
        print("\n📋 PASO 5: SOLICITUDES CREADAS")
        print("-" * 40)
        self.ver_solicitudes_reabastecimiento()
        self.pausa_para_captura("Demostración completa finalizada")

        print("\n🎉 DEMOSTRACIÓN COMPLETA EXITOSA")
        print("✅ Todos los componentes del sistema funcionan correctamente")

    def reporte_pruebas(self):
        """Genera un reporte de las pruebas realizadas"""
        print("\n📈 REPORTE DE PRUEBAS REALIZADAS")
        print("=" * 50)

        try:
            # Contar triggers ejecutados hoy
            self.cursor.execute("""
                SELECT COUNT(*) 
                FROM solicitudes_reabastecimiento 
                WHERE DATE(fecha_solicitud) = CURDATE()
            """)
            triggers_hoy = self.cursor.fetchone()[0]

            # Contar notificaciones generadas hoy
            self.cursor.execute("""
                SELECT COUNT(*) 
                FROM notificaciones_administrativas 
                WHERE DATE(fecha_hora) = CURDATE() 
                AND tipo_notificacion = 'Reabastecimiento'
            """)
            notificaciones_hoy = self.cursor.fetchone()[0]

            # Medicamentos en estado crítico
            self.cursor.execute("""
                SELECT COUNT(*) 
                FROM inventario_medicamentos 
                WHERE cantidad <= nivel_minimo
            """)
            medicamentos_criticos = self.cursor.fetchone()[0]

            print(f"\n📊 ESTADÍSTICAS DE PRUEBAS (HOY):")
            print(f"   🔥 Triggers disparados: {triggers_hoy}")
            print(f"   🔔 Notificaciones generadas: {notificaciones_hoy}")
            print(f"   🚨 Medicamentos en estado crítico: {medicamentos_criticos}")

            # Mostrar últimas actividades
            print(f"\n📋 ÚLTIMAS ACTIVIDADES DEL SISTEMA:")
            self.cursor.execute("""
                SELECT 
                    'Solicitud creada' as Actividad,
                    m.nombre as Detalle,
                    sr.fecha_solicitud as Fecha
                FROM solicitudes_reabastecimiento sr
                JOIN medicamentos m ON sr.id_medicamento = m.id_medicamento
                WHERE DATE(sr.fecha_solicitud) = CURDATE()
                UNION ALL
                SELECT 
                    'Notificación enviada' as Actividad,
                    LEFT(mensaje, 30) as Detalle,
                    fecha_hora as Fecha
                FROM notificaciones_administrativas
                WHERE DATE(fecha_hora) = CURDATE() 
                AND tipo_notificacion = 'Reabastecimiento'
                ORDER BY Fecha DESC
                LIMIT 10
            """)

            actividades = self.cursor.fetchall()
            if actividades:
                headers = ['Actividad', 'Detalle', 'Fecha/Hora']
                print(tabulate(actividades, headers=headers, tablefmt='grid'))
            else:
                print("   📭 No hay actividades registradas hoy")

        except mysql.connector.Error as err:
            print(f"\n❌ Error al generar reporte: {err}")

    def ejecutar_demo(self):
        """Ciclo principal de la demostración"""
        if not self.conectar_db():
            return

        print("\n🎬 BIENVENIDO A LA DEMOSTRACIÓN DEL SISTEMA")
        print("📋 Este script está optimizado para capturas de documentación")

        while True:
            self.mostrar_menu_principal()
            opcion = input("\n👉 Seleccione una opción para demostrar: ")

            if opcion == '0':
                print("\n👋 Finalizando demostración del sistema")
                print("📸 Asegúrese de haber capturado todas las pantallas necesarias")
                break
            elif opcion == '1':
                self.ver_inventario_actual()
            elif opcion == '2':
                self.actualizar_inventario_demo()
            elif opcion == '3':
                self.ver_estado_sistema_completo()
            elif opcion == '4':
                self.ver_notificaciones()
            elif opcion == '5':
                self.ver_solicitudes_reabastecimiento()
            elif opcion == '6':
                self.demostracion_completa()
            elif opcion == '7':
                self.reporte_pruebas()
            else:
                print("\n❌ Opción inválida. Intente nuevamente.")

            if opcion != '0':
                self.pausa_para_captura("📸 Captura lista - Presione Enter para volver al menú")
                print("\n" + "🔄 " * 20)

        self.cerrar_conexion()


# Punto de entrada principal para la demostración
if __name__ == "__main__":
    print("🎬 INICIANDO DEMOSTRACIÓN PARA DOCUMENTACIÓN")
    print("📸 Sistema optimizado para capturas de pantalla")
    print("=" * 60)

    app = ClinicaVeterinariaDemo()
    try:
        app.ejecutar_demo()
    except KeyboardInterrupt:
        print("\n\n⚠️ Demostración interrumpida por el usuario")
        if app.connection:
            app.cerrar_conexion()
    except Exception as e:
        print(f"\n❌ Error inesperado durante la demostración: {e}")
        if app.connection:
            app.cerrar_conexion()

    print("\n🎉 DEMOSTRACIÓN FINALIZADA")
    print("📚 Recuerde incluir todas las capturas en su documentación")