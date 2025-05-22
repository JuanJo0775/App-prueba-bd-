#!/usr/bin/env python3
"""
Aplicación Flask - Clínica Veterinaria Altavida
Sistema de Gestión con Automatizaciones
"""

from flask import Flask, render_template, request, jsonify, flash, redirect, url_for
import mysql.connector
from mysql.connector import Error
import datetime
from contextlib import contextmanager
import traceback
import os
from config import config


def create_app(config_name=None):
    """Factory function para crear la aplicación Flask"""
    if config_name is None:
        config_name = os.environ.get('FLASK_ENV', 'development')

    app = Flask(__name__)
    app.config.from_object(config.get(config_name, config['default']))

    return app


app = create_app()


@contextmanager
def get_db_connection():
    """Context manager para manejo de conexiones a la base de datos"""
    connection = None
    try:
        db_config = {
            'host': app.config.get('DB_HOST', 'localhost'),
            'database': app.config.get('DB_NAME', 'clinica_veterinaria_altavida'),
            'user': app.config.get('DB_USER', 'root'),
            'password': app.config.get('DB_PASSWORD', ''),
            'charset': app.config.get('DB_CHARSET', 'utf8mb4'),
            'autocommit': False,
            'use_unicode': True
        }
        connection = mysql.connector.connect(**db_config)
        yield connection
    except Error as e:
        print(f"Error de base de datos: {e}")
        if connection:
            connection.rollback()
        raise
    finally:
        if connection and connection.is_connected():
            connection.close()


def get_safe_stats():
    """Obtiene estadísticas de forma segura, retorna valores por defecto si hay error"""
    try:
        with get_db_connection() as conn:
            cursor = conn.cursor(dictionary=True)

            stats = {}

            cursor.execute("SELECT COUNT(*) as total FROM mascotas WHERE activo = TRUE")
            stats['total_mascotas'] = cursor.fetchone()['total']

            cursor.execute("SELECT COUNT(*) as total FROM veterinarios WHERE activo = TRUE")
            stats['total_veterinarios'] = cursor.fetchone()['total']

            cursor.execute("SELECT COUNT(*) as total FROM citas WHERE DATE(fecha_hora) = CURDATE()")
            stats['citas_hoy'] = cursor.fetchone()['total']

            cursor.execute("SELECT COUNT(*) as total FROM inventario_medicamentos WHERE cantidad <= nivel_minimo")
            stats['medicamentos_criticos'] = cursor.fetchone()['total']

            cursor.execute("SELECT COUNT(*) as total FROM notificaciones_administrativas WHERE leida = FALSE")
            stats['notificaciones_pendientes'] = cursor.fetchone()['total']

            return stats
    except Exception as e:
        print(f"Error al obtener estadísticas: {e}")
        return {
            'total_mascotas': 0,
            'total_veterinarios': 0,
            'citas_hoy': 0,
            'medicamentos_criticos': 0,
            'notificaciones_pendientes': 0
        }


@app.route('/')
def index():
    """Página principal con dashboard"""
    stats = get_safe_stats()
    return render_template('index.html', stats=stats)


@app.route('/api/historias-clinicas')
def get_historias_clinicas():
    """API para obtener historias clínicas"""
    try:
        with get_db_connection() as conn:
            cursor = conn.cursor(dictionary=True)
            cursor.execute("""
                SELECT hc.id_historia_clinica, m.nombre as mascota, 
                       e.nombre as especie, r.nombre as raza,
                       hc.fecha
                FROM historias_clinicas hc
                JOIN mascotas m ON hc.id_mascota = m.id_mascota
                JOIN especies e ON m.id_especie = e.id_especie
                JOIN razas r ON m.id_raza = r.id_raza
                ORDER BY hc.id_historia_clinica DESC
                LIMIT 20
            """)
            return jsonify(cursor.fetchall())
    except Exception as e:
        return jsonify({'error': str(e)}), 500


@app.route('/api/tratamientos')
def get_tratamientos():
    """API para obtener tratamientos"""
    try:
        with get_db_connection() as conn:
            cursor = conn.cursor(dictionary=True)
            cursor.execute("""
                SELECT id_tratamiento, nombre, tipo, precio
                FROM tratamientos
                ORDER BY nombre
            """)
            return jsonify(cursor.fetchall())
    except Exception as e:
        return jsonify({'error': str(e)}), 500


@app.route('/api/medicamentos')
def get_medicamentos():
    """API para obtener medicamentos e inventario"""
    try:
        with get_db_connection() as conn:
            cursor = conn.cursor(dictionary=True)
            cursor.execute("""
                SELECT m.id_medicamento, m.nombre, im.cantidad, 
                       im.nivel_minimo, im.nivel_optimo,
                       CASE 
                           WHEN im.cantidad <= im.nivel_minimo THEN 'crítico'
                           WHEN im.cantidad <= (im.nivel_minimo * 1.5) THEN 'bajo'
                           ELSE 'normal'
                       END as estado
                FROM medicamentos m
                JOIN inventario_medicamentos im ON m.id_medicamento = im.id_medicamento
                ORDER BY im.cantidad ASC
            """)
            return jsonify(cursor.fetchall())
    except Exception as e:
        return jsonify({'error': str(e)}), 500


@app.route('/api/veterinarios')
def get_veterinarios():
    """API para obtener veterinarios"""
    try:
        with get_db_connection() as conn:
            cursor = conn.cursor(dictionary=True)
            cursor.execute("""
                SELECT v.id_veterinario, v.nombre, v.apellido, 
                       v.especialidad, c.nombre as cargo
                FROM veterinarios v
                JOIN cargos c ON v.id_cargo = c.id_cargo
                WHERE v.activo = TRUE
                ORDER BY v.nombre
            """)
            return jsonify(cursor.fetchall())
    except Exception as e:
        return jsonify({'error': str(e)}), 500


@app.route('/api/diagnosticos')
def get_diagnosticos():
    """API para obtener diagnósticos"""
    try:
        with get_db_connection() as conn:
            cursor = conn.cursor(dictionary=True)
            cursor.execute("""
                SELECT id_diagnostico, nombre, categoria, riesgo_vital
                FROM diagnosticos
                ORDER BY nombre
            """)
            return jsonify(cursor.fetchall())
    except Exception as e:
        return jsonify({'error': str(e)}), 500


@app.route('/api/citas-facturar')
def get_citas_facturar():
    """API para obtener citas disponibles para facturar"""
    try:
        with get_db_connection() as conn:
            cursor = conn.cursor(dictionary=True)
            cursor.execute("""
                SELECT c.id_cita, m.nombre as mascota, v.nombre as veterinario, 
                       c.fecha_hora, p.nombre as propietario, p.id_propietario
                FROM citas c
                JOIN mascotas m ON c.id_mascota = m.id_mascota
                JOIN veterinarios v ON c.id_veterinario = v.id_veterinario
                JOIN propietarios p ON m.id_propietario = p.id_propietario
                WHERE c.estado = 'Completada'
                AND c.id_cita NOT IN (SELECT id_cita FROM detalle_facturas WHERE id_cita IS NOT NULL)
                ORDER BY c.fecha_hora DESC
                LIMIT 20
            """)
            return jsonify(cursor.fetchall())
    except Exception as e:
        return jsonify({'error': str(e)}), 500


@app.route('/api/registrar-tratamiento', methods=['POST'])
def registrar_tratamiento():
    """API para registrar un tratamiento"""
    try:
        data = request.get_json()

        with get_db_connection() as conn:
            cursor = conn.cursor()
            cursor.execute("""
                INSERT INTO tratamientos_aplicados 
                (id_historia_clinica, id_tratamiento, fecha_hora, id_veterinario, observaciones)
                VALUES (%s, %s, NOW(), %s, %s)
            """, (data['id_historia'], data['id_tratamiento'],
                  data['id_veterinario'], data.get('observaciones', 'Tratamiento registrado desde la web')))

            conn.commit()
            return jsonify({'success': True, 'message': 'Tratamiento registrado exitosamente'})

    except mysql.connector.Error as err:
        if "Tratamiento incompatible" in str(err):
            return jsonify({
                'success': False,
                'message': 'El tratamiento no es compatible con la especie/raza de la mascota'
            }), 400
        else:
            return jsonify({'success': False, 'message': str(err)}), 500
    except Exception as e:
        return jsonify({'success': False, 'message': str(e)}), 500


@app.route('/api/actualizar-inventario', methods=['POST'])
def actualizar_inventario():
    """API para actualizar inventario"""
    try:
        data = request.get_json()

        with get_db_connection() as conn:
            cursor = conn.cursor()
            cursor.execute("""
                UPDATE inventario_medicamentos
                SET cantidad = %s, fecha_actualizacion = NOW()
                WHERE id_medicamento = %s
            """, (data['cantidad'], data['id_medicamento']))

            conn.commit()
            return jsonify({'success': True, 'message': 'Inventario actualizado exitosamente'})

    except Exception as e:
        return jsonify({'success': False, 'message': str(e)}), 500


@app.route('/api/facturar-cita', methods=['POST'])
def facturar_cita():
    """API para facturar una cita"""
    try:
        data = request.get_json()

        with get_db_connection() as conn:
            cursor = conn.cursor()

            # Crear factura
            cursor.execute("""
                INSERT INTO facturas (id_propietario, fecha_emision, total, estado)
                VALUES (%s, NOW(), %s, 'Pendiente')
            """, (data['id_propietario'], data['total']))

            id_factura = cursor.lastrowid

            # Agregar detalle de factura
            cursor.execute("""
                INSERT INTO detalle_facturas 
                (id_factura, id_cita, cantidad, precio_unitario, subtotal)
                VALUES (%s, %s, 1, %s, %s)
            """, (id_factura, data['id_cita'], data['total'], data['total']))

            conn.commit()
            return jsonify({
                'success': True,
                'message': 'Factura creada exitosamente',
                'id_factura': id_factura
            })

    except mysql.connector.Error as err:
        if any(x in str(err) for x in ["evolución clínica", "diagnóstico", "tratamiento"]):
            return jsonify({
                'success': False,
                'message': 'La cita no cumple con los requisitos para facturación'
            }), 400
        else:
            return jsonify({'success': False, 'message': str(err)}), 500
    except Exception as e:
        return jsonify({'success': False, 'message': str(e)}), 500


@app.route('/api/registrar-diagnostico-critico', methods=['POST'])
def registrar_diagnostico_critico():
    """API para registrar diagnóstico crítico"""
    try:
        data = request.get_json()

        with get_db_connection() as conn:
            cursor = conn.cursor()
            cursor.execute("""
                UPDATE historias_clinicas
                SET id_diagnostico = %s
                WHERE id_historia_clinica = %s
            """, (data['id_diagnostico'], data['id_historia']))

            conn.commit()
            return jsonify({
                'success': True,
                'message': 'Diagnóstico crítico registrado. Se ha generado alerta automática.'
            })

    except Exception as e:
        return jsonify({'success': False, 'message': str(e)}), 500


@app.route('/api/reporte-diario')
def generar_reporte_diario():
    """API para generar reporte diario"""
    try:
        fecha = request.args.get('fecha')

        with get_db_connection() as conn:
            cursor = conn.cursor(dictionary=True)

            if fecha:
                cursor.callproc('generar_reporte_diario', [fecha])
            else:
                cursor.callproc('generar_reporte_diario', [None])

            reporte = []
            for result in cursor.stored_results():
                rows = result.fetchall()
                if rows:
                    reporte.extend(rows)

            return jsonify(reporte)

    except Exception as e:
        return jsonify({'error': str(e)}), 500


@app.route('/api/notificaciones')
def get_notificaciones():
    """API para obtener notificaciones"""
    try:
        with get_db_connection() as conn:
            cursor = conn.cursor(dictionary=True)
            cursor.execute("""
                SELECT tipo_notificacion, mensaje, dirigido_a, fecha_hora, leida
                FROM notificaciones_administrativas
                ORDER BY fecha_hora DESC
                LIMIT 50
            """)
            return jsonify(cursor.fetchall())
    except Exception as e:
        return jsonify({'error': str(e)}), 500


@app.route('/api/marcar-notificaciones-leidas', methods=['POST'])
def marcar_notificaciones_leidas():
    """API para marcar notificaciones como leídas"""
    try:
        with get_db_connection() as conn:
            cursor = conn.cursor()
            cursor.execute("""
                UPDATE notificaciones_administrativas
                SET leida = TRUE, fecha_lectura = NOW()
                WHERE leida = FALSE
            """)
            conn.commit()
            return jsonify({'success': True, 'message': 'Notificaciones marcadas como leídas'})
    except Exception as e:
        return jsonify({'success': False, 'message': str(e)}), 500


@app.route('/api/errores')
def get_errores():
    """API para obtener errores registrados"""
    try:
        with get_db_connection() as conn:
            cursor = conn.cursor(dictionary=True)
            cursor.execute("""
                SELECT tipo_error, descripcion, fecha_hora, usuario
                FROM registro_errores_clinicos
                ORDER BY fecha_hora DESC
                LIMIT 20
            """)
            return jsonify(cursor.fetchall())
    except Exception as e:
        return jsonify({'error': str(e)}), 500


@app.route('/favicon.ico')
def favicon():
    """Maneja la solicitud del favicon"""
    return '', 204


@app.errorhandler(404)
def not_found(error):
    """Maneja errores 404"""
    stats = get_safe_stats()
    return render_template('index.html', stats=stats), 404


@app.errorhandler(500)
def internal_error(error):
    """Maneja errores 500"""
    return jsonify({'error': 'Error interno del servidor'}), 500


if __name__ == '__main__':
    app.run(debug=True, host='0.0.0.0', port=5000)