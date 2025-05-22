#!/usr/bin/env python3
"""
Aplicación de Demostración - Clínica Veterinaria Altavida
Sistema de Gestión con Automatizaciones
"""

import mysql.connector
from mysql.connector import Error
import datetime
from tabulate import tabulate
import os


class ClinicaVeterinariaApp:
    def __init__(self):
        self.connection = None
        self.cursor = None

    def conectar_db(self):
        """Establece conexión con la base de datos"""
        try:
            self.connection = mysql.connector.connect(
                host='localhost',
                database='clinica_veterinaria',
                user='root',  # Cambiar según tu configuración
                password=''  # Cambiar según tu configuración
            )
            if self.connection.is_connected():
                self.cursor = self.connection.cursor()
                print("✅ Conexión exitosa a la base de datos")
                return True
        except Error as e:
            print(f"❌ Error al conectar: {e}")
            return False

    def cerrar_conexion(self):
        """Cierra la conexión con la base de datos"""
        if self.connection and self.connection.is_connected():
            self.cursor.close()
            self.connection.close()
            print("🔒 Conexión cerrada")

    def limpiar_pantalla(self):
        """Limpia la pantalla de la consola"""
        os.system('cls' if os.name == 'nt' else 'clear')

    def mostrar_menu_principal(self):
        """Muestra el menú principal de la aplicación"""
        print("\n" + "=" * 50)
        print("🏥 CLÍNICA VETERINARIA ALTAVIDA")
        print("Sistema de Gestión con Automatizaciones")
        print("=" * 50)
        print("\n1. 🐾 Registrar Tratamiento (Prueba validación)")
        print("2. 💊 Actualizar Inventario (Prueba reabastecimiento)")
        print("3. 💰 Facturar Cita (Prueba validación)")
        print("4. ⚕️  Registrar Diagnóstico Crítico")
        print("5. 📊 Generar Reporte Diario")
        print("6. 🔍 Ver Estado del Sistema")
        print("7. 📋 Ver Errores Registrados")
        print("8. 🔔 Ver Notificaciones")
        print("9. ✅ Simular Consulta Completa")
        print("0. ❌ Salir")
        print("=" * 50)

    def registrar_tratamiento(self):
        """Prueba la validación de tratamientos según especie/raza"""
        print("\n🐾 REGISTRO DE TRATAMIENTO")
        print("-" * 30)

        # Mostrar historias clínicas disponibles
        self.cursor.execute("""
            SELECT hc.id_historia_clinica, m.nombre as mascota, e.nombre as especie, r.nombre as raza
            FROM historias_clinicas hc
            JOIN mascotas m ON hc.id_mascota = m.id_mascota
            JOIN especies e ON m.id_especie = e.id_especie
            JOIN razas r ON m.id_raza = r.id_raza
            ORDER BY hc.id_historia_clinica DESC
            LIMIT 10
        """)

        historias = self.cursor.fetchall()
        print("\nHistorias Clínicas Disponibles:")
        print(tabulate(historias, headers=['ID', 'Mascota', 'Especie', 'Raza'], tablefmt='grid'))

        # Mostrar tratamientos disponibles
        self.cursor.execute("""
            SELECT id_tratamiento, nombre, tipo
            FROM tratamientos
            LIMIT 10
        """)

        tratamientos = self.cursor.fetchall()
        print("\nTratamientos Disponibles:")
        print(tabulate(tratamientos, headers=['ID', 'Nombre', 'Tipo'], tablefmt='grid'))

        try:
            id_historia = int(input("\nID Historia Clínica: "))
            id_tratamiento = int(input("ID Tratamiento: "))
            id_veterinario = int(input("ID Veterinario: "))

            # Intentar registrar el tratamiento
            query = """
                INSERT INTO tratamientos_aplicados 
                (id_historia_clinica, id_tratamiento, fecha_hora, id_veterinario, observaciones)
                VALUES (%s, %s, NOW(), %s, 'Tratamiento de prueba')
            """

            self.cursor.execute(query, (id_historia, id_tratamiento, id_veterinario))
            self.connection.commit()
            print("\n✅ Tratamiento registrado exitosamente")

        except mysql.connector.Error as err:
            if "Tratamiento incompatible" in str(err):
                print(f"\n❌ Error de validación: {err}")
                print("El tratamiento no es compatible con la especie/raza de la mascota")
            else:
                print(f"\n❌ Error: {err}")
        except ValueError:
            print("\n❌ Error: Ingrese valores numéricos válidos")

    def actualizar_inventario(self):
        """Prueba el trigger de reabastecimiento automático"""
        print("\n💊 ACTUALIZACIÓN DE INVENTARIO")
        print("-" * 30)

        # Mostrar medicamentos y su inventario
        self.cursor.execute("""
            SELECT m.id_medicamento, m.nombre, im.cantidad, im.nivel_minimo, im.nivel_optimo
            FROM medicamentos m
            JOIN inventario_medicamentos im ON m.id_medicamento = im.id_medicamento
            ORDER BY im.cantidad ASC
            LIMIT 10
        """)

        inventario = self.cursor.fetchall()
        print("\nInventario Actual:")
        print(tabulate(inventario,
                       headers=['ID', 'Medicamento', 'Cantidad', 'Nivel Mínimo', 'Nivel Óptimo'],
                       tablefmt='grid'))

        try:
            id_medicamento = int(input("\nID Medicamento a actualizar: "))
            nueva_cantidad = int(input("Nueva cantidad: "))

            # Actualizar cantidad
            self.cursor.execute("""
                UPDATE inventario_medicamentos
                SET cantidad = %s, fecha_actualizacion = NOW()
                WHERE id_medicamento = %s
            """, (nueva_cantidad, id_medicamento))

            self.connection.commit()
            print("\n✅ Inventario actualizado")

            # Verificar si se generó notificación
            self.cursor.execute("""
                SELECT mensaje FROM notificaciones_administrativas
                WHERE tipo_notificacion = 'Reabastecimiento'
                ORDER BY fecha_hora DESC
                LIMIT 1
            """)

            notificacion = self.cursor.fetchone()
            if notificacion:
                print(f"\n🔔 Notificación generada: {notificacion[0]}")

        except ValueError:
            print("\n❌ Error: Ingrese valores numéricos válidos")
        except mysql.connector.Error as err:
            print(f"\n❌ Error: {err}")

    def facturar_cita(self):
        """Prueba la validación de facturación"""
        print("\n💰 FACTURACIÓN DE CITA")
        print("-" * 30)

        # Mostrar citas disponibles para facturar
        self.cursor.execute("""
            SELECT c.id_cita, m.nombre as mascota, v.nombre as veterinario, c.fecha_hora
            FROM citas c
            JOIN mascotas m ON c.id_mascota = m.id_mascota
            JOIN veterinarios v ON c.id_veterinario = v.id_veterinario
            WHERE c.estado = 'Completada'
            AND c.id_cita NOT IN (SELECT id_cita FROM detalle_facturas WHERE id_cita IS NOT NULL)
            ORDER BY c.fecha_hora DESC
            LIMIT 10
        """)

        citas = self.cursor.fetchall()
        print("\nCitas Disponibles para Facturar:")
        print(tabulate(citas, headers=['ID', 'Mascota', 'Veterinario', 'Fecha'], tablefmt='grid'))

        try:
            id_cita = int(input("\nID Cita a facturar: "))
            id_propietario = int(input("ID Propietario: "))

            # Crear factura
            self.cursor.execute("""
                INSERT INTO facturas (id_propietario, fecha_emision, total, estado)
                VALUES (%s, NOW(), 0, 'Pendiente')
            """, (id_propietario,))

            id_factura = self.cursor.lastrowid

            # Intentar agregar detalle de factura
            self.cursor.execute("""
                INSERT INTO detalle_facturas 
                (id_factura, id_cita, cantidad, precio_unitario, subtotal)
                VALUES (%s, %s, 1, 50000, 50000)
            """, (id_factura, id_cita))

            self.connection.commit()
            print("\n✅ Factura creada exitosamente")

        except mysql.connector.Error as err:
            if "evolución clínica" in str(err) or "diagnóstico" in str(err) or "tratamiento" in str(err):
                print(f"\n❌ Error de validación: {err}")
                print("La cita no cumple con los requisitos para facturación")
            else:
                print(f"\n❌ Error: {err}")
        except ValueError:
            print("\n❌ Error: Ingrese valores numéricos válidos")

    def registrar_diagnostico_critico(self):
        """Prueba el registro de diagnósticos de riesgo vital"""
        print("\n⚕️ REGISTRO DE DIAGNÓSTICO CRÍTICO")
        print("-" * 30)

        # Mostrar diagnósticos de riesgo vital
        self.cursor.execute("""
            SELECT id_diagnostico, nombre, categoria
            FROM diagnosticos
            WHERE riesgo_vital = TRUE
        """)

        diagnosticos_criticos = self.cursor.fetchall()
        print("\nDiagnósticos de Riesgo Vital:")
        print(tabulate(diagnosticos_criticos, headers=['ID', 'Nombre', 'Categoría'], tablefmt='grid'))

        # Mostrar historias clínicas activas
        self.cursor.execute("""
            SELECT hc.id_historia_clinica, m.nombre as mascota
            FROM historias_clinicas hc
            JOIN mascotas m ON hc.id_mascota = m.id_mascota
            WHERE hc.tiene_alta = FALSE
            ORDER BY hc.fecha DESC
            LIMIT 10
        """)

        historias = self.cursor.fetchall()
        print("\nHistorias Clínicas Activas:")
        print(tabulate(historias, headers=['ID', 'Mascota'], tablefmt='grid'))

        try:
            id_historia = int(input("\nID Historia Clínica: "))
            id_diagnostico = int(input("ID Diagnóstico de riesgo vital: "))

            # Actualizar historia clínica con diagnóstico crítico
            self.cursor.execute("""
                UPDATE historias_clinicas
                SET id_diagnostico = %s
                WHERE id_historia_clinica = %s
            """, (id_diagnostico, id_historia))

            self.connection.commit()
            print("\n✅ Diagnóstico crítico registrado")
            print("Se ha generado alerta automática y notificación al Director Médico")

        except ValueError:
            print("\n❌ Error: Ingrese valores numéricos válidos")
        except mysql.connector.Error as err:
            print(f"\n❌ Error: {err}")

    def generar_reporte_diario(self):
        """Genera el reporte diario consolidado"""
        print("\n📊 REPORTE DIARIO")
        print("-" * 30)

        fecha = input("\nFecha del reporte (YYYY-MM-DD) [Enter para hoy]: ")

        try:
            if fecha:
                self.cursor.callproc('generar_reporte_diario', [fecha])
            else:
                self.cursor.callproc('generar_reporte_diario', [None])

            # Obtener los resultados del procedimiento
            for result in self.cursor.stored_results():
                rows = result.fetchall()
                if rows:
                    headers = [desc[0] for desc in result.description]
                    print(f"\n{rows[0][0]}")  # Título de la sección
                    print(tabulate(rows, headers=headers, tablefmt='grid'))

        except mysql.connector.Error as err:
            print(f"\n❌ Error: {err}")

    def ver_estado_sistema(self):
        """Muestra el estado general del sistema"""
        print("\n🔍 ESTADO DEL SISTEMA")
        print("-" * 30)

        try:
            self.cursor.callproc('verificar_estado_sistema')

            for result in self.cursor.stored_results():
                rows = result.fetchall()
                if rows:
                    # El primer elemento es el título de la sección
                    if len(rows[0]) == 1:
                        print(f"\n{rows[0][0]}")
                    else:
                        headers = [desc[0] for desc in result.description]
                        print(tabulate(rows, headers=headers, tablefmt='grid'))

        except mysql.connector.Error as err:
            print(f"\n❌ Error: {err}")

    def ver_errores_registrados(self):
        """Muestra los últimos errores registrados"""
        print("\n📋 ERRORES REGISTRADOS")
        print("-" * 30)

        self.cursor.execute("""
            SELECT tipo_error, descripcion, fecha_hora, usuario
            FROM registro_errores_clinicos
            ORDER BY fecha_hora DESC
            LIMIT 10
        """)

        errores = self.cursor.fetchall()
        if errores:
            print(tabulate(errores,
                           headers=['Tipo Error', 'Descripción', 'Fecha/Hora', 'Usuario'],
                           tablefmt='grid'))
        else:
            print("\n✅ No hay errores registrados")

    def ver_notificaciones(self):
        """Muestra las notificaciones pendientes"""
        print("\n🔔 NOTIFICACIONES")
        print("-" * 30)

        self.cursor.execute("""
            SELECT tipo_notificacion, mensaje, dirigido_a, fecha_hora
            FROM notificaciones_administrativas
            WHERE leida = FALSE
            ORDER BY fecha_hora DESC
            LIMIT 10
        """)

        notificaciones = self.cursor.fetchall()
        if notificaciones:
            print(tabulate(notificaciones,
                           headers=['Tipo', 'Mensaje', 'Dirigido a', 'Fecha/Hora'],
                           tablefmt='grid'))

            marcar = input("\n¿Marcar todas como leídas? (s/n): ")
            if marcar.lower() == 's':
                self.cursor.execute("""
                    UPDATE notificaciones_administrativas
                    SET leida = TRUE, fecha_lectura = NOW()
                    WHERE leida = FALSE
                """)
                self.connection.commit()
                print("✅ Notificaciones marcadas como leídas")
        else:
            print("\n✅ No hay notificaciones pendientes")

    def simular_consulta_completa(self):
        """Simula una consulta completa para probar todas las automatizaciones"""
        print("\n✅ SIMULACIÓN DE CONSULTA COMPLETA")
        print("-" * 30)

        try:
            id_mascota = int(input("ID Mascota: "))
            id_veterinario = int(input("ID Veterinario: "))
            id_diagnostico = int(input("ID Diagnóstico: "))
            id_tratamiento = int(input("ID Tratamiento: "))
            id_medicamento = int(input("ID Medicamento (0 para ninguno): "))

            if id_medicamento == 0:
                id_medicamento = None

            # Llamar al procedimiento de simulación
            self.cursor.callproc('simular_consulta_completa',
                                 [id_mascota, id_veterinario, id_diagnostico,
                                  id_tratamiento, id_medicamento])

            # Obtener resultados
            for result in self.cursor.stored_results():
                rows = result.fetchall()
                if rows:
                    print(f"\n{rows[0][0]}")  # Mensaje
                    if len(rows[0]) > 1:
                        print(f"ID Cita: {rows[0][1]}")
                        print(f"ID Historia Clínica: {rows[0][2]}")

            self.connection.commit()

        except ValueError:
            print("\n❌ Error: Ingrese valores numéricos válidos")
        except mysql.connector.Error as err:
            print(f"\n❌ Error: {err}")

    def ejecutar(self):
        """Ciclo principal de la aplicación"""
        if not self.conectar_db():
            return

        while True:
            self.mostrar_menu_principal()
            opcion = input("\nSeleccione una opción: ")

            if opcion == '0':
                print("\n👋 Gracias por usar el sistema")
                break
            elif opcion == '1':
                self.registrar_tratamiento()
            elif opcion == '2':
                self.actualizar_inventario()
            elif opcion == '3':
                self.facturar_cita()
            elif opcion == '4':
                self.registrar_diagnostico_critico()
            elif opcion == '5':
                self.generar_reporte_diario()
            elif opcion == '6':
                self.ver_estado_sistema()
            elif opcion == '7':
                self.ver_errores_registrados()
            elif opcion == '8':
                self.ver_notificaciones()
            elif opcion == '9':
                self.simular_consulta_completa()
            else:
                print("\n❌ Opción inválida")

            input("\nPresione Enter para continuar...")
            self.limpiar_pantalla()

        self.cerrar_conexion()


# Punto de entrada principal
if __name__ == "__main__":
    app = ClinicaVeterinariaApp()
    try:
        app.ejecutar()
    except KeyboardInterrupt:
        print("\n\n⚠️ Aplicación interrumpida por el usuario")
        app.cerrar_conexion()
    except Exception as e:
        print(f"\n❌ Error inesperado: {e}")
        app.cerrar_conexion()