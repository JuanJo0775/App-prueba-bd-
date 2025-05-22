-- phpMyAdmin SQL Dump
-- version 5.2.1
-- https://www.phpmyadmin.net/
--
-- Servidor: 127.0.0.1
-- Tiempo de generación: 22-05-2025 a las 01:13:01
-- Versión del servidor: 10.4.32-MariaDB
-- Versión de PHP: 8.2.12

SET SQL_MODE = "NO_AUTO_VALUE_ON_ZERO";
START TRANSACTION;
SET time_zone = "+00:00";


/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!40101 SET NAMES utf8mb4 */;

--
-- Base de datos: `clinica_veterinaria_altavida`
--

DELIMITER $$
--
-- Procedimientos
--
CREATE DEFINER=`root`@`localhost` PROCEDURE `generar_reporte_diario` (IN `p_fecha` DATE)   BEGIN
    -- Variables
    DECLARE v_fecha_reporte DATE;

    -- Si no se proporciona fecha, usar la fecha actual
    SET v_fecha_reporte = IFNULL(p_fecha, CURDATE());

    -- Crear tabla temporal para el reporte consolidado
    CREATE TEMPORARY TABLE IF NOT EXISTS temp_reporte_diario (
        seccion VARCHAR(100),
        categoria VARCHAR(100),
        detalle TEXT,
        valor VARCHAR(50),
        orden INT
    );

    -- Limpiar tabla temporal
    TRUNCATE TABLE temp_reporte_diario;

    -- 1. Número de citas por médico
    INSERT INTO temp_reporte_diario (seccion, categoria, detalle, valor, orden)
    SELECT
        '1. CITAS POR MÉDICO' as seccion,
        v.especialidad as categoria,
        CONCAT(v.nombre, ' ', v.apellido) as detalle,
        COUNT(c.id_cita) as valor,
        1 as orden
    FROM veterinarios v
    LEFT JOIN citas c ON v.id_veterinario = c.id_veterinario
        AND DATE(c.fecha_hora) = v_fecha_reporte
    WHERE v.activo = TRUE
    GROUP BY v.id_veterinario, v.nombre, v.apellido, v.especialidad
    ORDER BY COUNT(c.id_cita) DESC;

    -- 2. Diagnósticos registrados por tipo
    INSERT INTO temp_reporte_diario (seccion, categoria, detalle, valor, orden)
    SELECT
        '2. DIAGNÓSTICOS POR TIPO' as seccion,
        d.categoria as categoria,
        d.nombre as detalle,
        COUNT(hc.id_historia_clinica) as valor,
        2 as orden
    FROM diagnosticos d
    LEFT JOIN historias_clinicas hc ON d.id_diagnostico = hc.id_diagnostico
        AND DATE(hc.fecha) = v_fecha_reporte
    GROUP BY d.id_diagnostico, d.categoria, d.nombre
    HAVING COUNT(hc.id_historia_clinica) > 0
    ORDER BY d.categoria, COUNT(hc.id_historia_clinica) DESC;

    -- 3. Medicamentos aplicados con lote y vencimiento
    INSERT INTO temp_reporte_diario (seccion, categoria, detalle, valor, orden)
    SELECT DISTINCT
        '3. MEDICAMENTOS APLICADOS' as seccion,
        CASE
            WHEN DATEDIFF(m.fecha_vencimiento, CURDATE()) <= 30 THEN 'PRÓXIMO A VENCER'
            WHEN DATEDIFF(m.fecha_vencimiento, CURDATE()) <= 90 THEN 'VIGILAR'
            ELSE 'VIGENTE'
        END as categoria,
        CONCAT(m.nombre, ' - Lote: ', m.lote) as detalle,
        DATE_FORMAT(m.fecha_vencimiento, '%d/%m/%Y') as valor,
        3 as orden
    FROM tratamientos_aplicados ta
    INNER JOIN medicamentos m ON ta.id_medicamento = m.id_medicamento
    WHERE DATE(ta.fecha_hora) = v_fecha_reporte
    ORDER BY m.fecha_vencimiento ASC;

    -- 4. Alertas críticas del día
    INSERT INTO temp_reporte_diario (seccion, categoria, detalle, valor, orden)
    SELECT
        '4. ALERTAS CRÍTICAS' as seccion,
        CASE
            WHEN ec.estado = 'Activo' THEN 'ACTIVA'
            ELSE 'RESUELTA'
        END as categoria,
        CONCAT('Mascota: ', m.nombre, ' - ', ec.descripcion) as detalle,
        TIME_FORMAT(ec.fecha_hora, '%H:%i') as valor,
        4 as orden
    FROM eventos_criticos ec
    INNER JOIN mascotas m ON ec.id_mascota = m.id_mascota
    WHERE DATE(ec.fecha_hora) = v_fecha_reporte
    ORDER BY ec.fecha_hora DESC;

    -- Agregar resumen del día
    INSERT INTO temp_reporte_diario (seccion, categoria, detalle, valor, orden)
    SELECT
        '5. RESUMEN DEL DÍA' as seccion,
        'ESTADÍSTICAS' as categoria,
        'Total de citas atendidas' as detalle,
        COUNT(*) as valor,
        5 as orden
    FROM citas
    WHERE DATE(fecha_hora) = v_fecha_reporte
    AND estado = 'Completada';

    INSERT INTO temp_reporte_diario (seccion, categoria, detalle, valor, orden)
    SELECT
        '5. RESUMEN DEL DÍA' as seccion,
        'ESTADÍSTICAS' as categoria,
        'Total de tratamientos aplicados' as detalle,
        COUNT(*) as valor,
        5 as orden
    FROM tratamientos_aplicados
    WHERE DATE(fecha_hora) = v_fecha_reporte;

    INSERT INTO temp_reporte_diario (seccion, categoria, detalle, valor, orden)
    SELECT
        '5. RESUMEN DEL DÍA' as seccion,
        'ESTADÍSTICAS' as categoria,
        'Medicamentos en nivel crítico' as detalle,
        COUNT(*) as valor,
        5 as orden
    FROM inventario_medicamentos
    WHERE cantidad <= nivel_minimo;

    -- Mostrar el reporte
    SELECT
        seccion,
        categoria,
        detalle,
        valor
    FROM temp_reporte_diario
    ORDER BY orden, seccion, categoria, detalle;

    -- Limpiar tabla temporal
    DROP TEMPORARY TABLE IF EXISTS temp_reporte_diario;
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `simular_consulta_completa` (IN `p_id_mascota` INT, IN `p_id_veterinario` INT, IN `p_id_diagnostico` INT, IN `p_id_tratamiento` INT, IN `p_id_medicamento` INT)   BEGIN
    DECLARE v_id_cita INT;
    DECLARE v_id_historia_clinica INT;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SELECT 'Error en la simulación' as mensaje;
    END;

    START TRANSACTION;

    -- 1. Crear cita
    INSERT INTO citas (id_mascota, id_veterinario, fecha_hora, motivo, estado)
    VALUES (p_id_mascota, p_id_veterinario, NOW(), 'Consulta de prueba', 'Completada');

    SET v_id_cita = LAST_INSERT_ID();

    -- 2. Crear historia clínica
    INSERT INTO historias_clinicas (
        id_cita, id_mascota, id_veterinario, id_diagnostico,
        fecha, anamnesis, exploracion, estado_general,
        temperatura, peso, evolucion, tiene_alta
    )
    VALUES (
        v_id_cita, p_id_mascota, p_id_veterinario, p_id_diagnostico,
        NOW(), 'Anamnesis de prueba', 'Exploración normal', 'Bueno',
        38.5, 15.0, 'Evolución favorable', FALSE
    );

    SET v_id_historia_clinica = LAST_INSERT_ID();

    -- 3. Aplicar tratamiento
    INSERT INTO tratamientos_aplicados (
        id_historia_clinica, id_tratamiento, id_medicamento,
        fecha_hora, dosis, observaciones, id_veterinario
    )
    VALUES (
        v_id_historia_clinica, p_id_tratamiento, p_id_medicamento,
        NOW(), '10mg', 'Tratamiento de prueba', p_id_veterinario
    );

    COMMIT;

    SELECT 'Simulación completada exitosamente' as mensaje,
           v_id_cita as id_cita,
           v_id_historia_clinica as id_historia_clinica;
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `verificar_estado_sistema` ()   BEGIN
    -- Medicamentos en nivel crítico
    SELECT 'MEDICAMENTOS EN NIVEL CRÍTICO' as seccion;
    SELECT
        m.nombre,
        im.cantidad as cantidad_actual,
        im.nivel_minimo,
        im.nivel_optimo
    FROM inventario_medicamentos im
    INNER JOIN medicamentos m ON im.id_medicamento = m.id_medicamento
    WHERE im.cantidad <= im.nivel_minimo;

    -- Eventos críticos activos
    SELECT 'EVENTOS CRÍTICOS ACTIVOS' as seccion;
    SELECT
        ec.id_evento,
        m.nombre as mascota,
        d.nombre as diagnostico,
        ec.fecha_hora,
        ec.descripcion
    FROM eventos_criticos ec
    INNER JOIN mascotas m ON ec.id_mascota = m.id_mascota
    INNER JOIN diagnosticos d ON ec.id_diagnostico = d.id_diagnostico
    WHERE ec.estado = 'Activo';

    -- Notificaciones pendientes
    SELECT 'NOTIFICACIONES PENDIENTES' as seccion;
    SELECT
        tipo_notificacion,
        mensaje,
        dirigido_a,
        fecha_hora
    FROM notificaciones_administrativas
    WHERE leida = FALSE
    ORDER BY fecha_hora DESC
    LIMIT 10;

    -- Solicitudes de reabastecimiento pendientes
    SELECT 'SOLICITUDES DE REABASTECIMIENTO PENDIENTES' as seccion;
    SELECT
        sr.id_solicitud,
        m.nombre as medicamento,
        sr.cantidad_actual,
        sr.cantidad_solicitada,
        sr.fecha_solicitud
    FROM solicitudes_reabastecimiento sr
    INNER JOIN medicamentos m ON sr.id_medicamento = m.id_medicamento
    WHERE sr.estado = 'Pendiente';
END$$

DELIMITER ;

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `altas_medicas`
--

CREATE TABLE `altas_medicas` (
  `id_alta` int(11) NOT NULL,
  `id_historia_clinica` int(11) NOT NULL,
  `id_veterinario` int(11) NOT NULL,
  `fecha_hora` datetime NOT NULL,
  `observaciones` text DEFAULT NULL,
  `recomendaciones` text DEFAULT NULL,
  `seguimiento_requerido` tinyint(1) DEFAULT 0
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Volcado de datos para la tabla `altas_medicas`
--

INSERT INTO `altas_medicas` (`id_alta`, `id_historia_clinica`, `id_veterinario`, `fecha_hora`, `observaciones`, `recomendaciones`, `seguimiento_requerido`) VALUES
(1, 1, 1, '2023-04-10 10:00:00', 'Alta por revisión anual completada', 'Mantener alimentación y ejercicio habitual', 0),
(2, 2, 1, '2023-04-10 10:40:00', 'Alta tras vacunación', 'Observar posibles reacciones en las próximas 24h', 0),
(3, 3, 2, '2023-04-12 09:00:00', 'Alta tras tratamiento de gastroenteritis', 'Dieta blanda durante 3 días, completar tratamiento antibiótico', 1),
(4, 4, 3, '2023-04-10 14:40:00', 'Alta tras revisión posquirúrgica', 'Mantener collar isabelino 7 días más', 1),
(5, 5, 4, '2023-04-10 16:00:00', 'Alta tras limpieza dental', 'Revisar alimentación para prevenir sarro', 0),
(6, 6, 5, '2023-04-10 17:00:00', 'Alta con tratamiento para dermatitis', 'Completar tratamiento, evitar alergenos, seguimiento en 10 días', 1);

--
-- Disparadores `altas_medicas`
--
DELIMITER $$
CREATE TRIGGER `validar_alta_medica` BEFORE INSERT ON `altas_medicas` FOR EACH ROW BEGIN
    DECLARE v_tiene_evento_critico_activo BOOLEAN DEFAULT FALSE;
    DECLARE v_es_director_medico BOOLEAN DEFAULT FALSE;

    -- Verificar si hay eventos críticos activos
    SELECT COUNT(*) > 0 INTO v_tiene_evento_critico_activo
    FROM eventos_criticos ec
    WHERE ec.id_historia_clinica = NEW.id_historia_clinica
    AND ec.estado = 'Activo';

    IF v_tiene_evento_critico_activo THEN
        -- Verificar si quien firma el alta es el director médico
        SELECT COUNT(*) > 0 INTO v_es_director_medico
        FROM veterinarios v
        INNER JOIN cargos c ON v.id_cargo = c.id_cargo
        WHERE v.id_veterinario = NEW.id_veterinario
        AND c.nombre = 'Director Médico';

        IF NOT v_es_director_medico THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Error: Solo el Director Médico puede autorizar el alta de pacientes con diagnóstico de riesgo vital';
        ELSE
            -- Si es el director, actualizar el evento crítico a resuelto
            UPDATE eventos_criticos
            SET estado = 'Resuelto',
                fecha_resolucion = NOW()
            WHERE id_historia_clinica = NEW.id_historia_clinica
            AND estado = 'Activo';
        END IF;
    END IF;
END
$$
DELIMITER ;

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `cargos`
--

CREATE TABLE `cargos` (
  `id_cargo` int(11) NOT NULL,
  `nombre` varchar(50) NOT NULL,
  `descripcion` text DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Volcado de datos para la tabla `cargos`
--

INSERT INTO `cargos` (`id_cargo`, `nombre`, `descripcion`) VALUES
(1, 'Veterinario General', 'Médico veterinario encargado de atención general de mascotas'),
(2, 'Jefe Clínico', 'Supervisa al equipo médico y aprueba procedimientos especiales'),
(3, 'Director Médico', 'Responsable de toda el área médica de la clínica'),
(4, 'Especialista en Cirugía', 'Veterinario especializado en procedimientos quirúrgicos'),
(5, 'Especialista en Dermatología', 'Veterinario especializado en problemas de piel');

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `citas`
--

CREATE TABLE `citas` (
  `id_cita` int(11) NOT NULL,
  `id_mascota` int(11) NOT NULL,
  `id_veterinario` int(11) NOT NULL,
  `fecha_hora` datetime NOT NULL,
  `motivo` varchar(255) NOT NULL,
  `estado` enum('Programada','Confirmada','Cancelada','Completada') DEFAULT 'Programada',
  `notas` text DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Volcado de datos para la tabla `citas`
--

INSERT INTO `citas` (`id_cita`, `id_mascota`, `id_veterinario`, `fecha_hora`, `motivo`, `estado`, `notas`) VALUES
(1, 1, 1, '2023-04-10 09:00:00', 'Revisión anual', 'Completada', 'Mascota en buen estado general'),
(2, 2, 1, '2023-04-10 10:00:00', 'Vacunación', 'Completada', 'Se aplicó vacuna antirrábica'),
(3, 3, 2, '2023-04-10 11:00:00', 'Problemas digestivos', 'Completada', 'Presenta vómitos desde hace 2 días'),
(4, 4, 3, '2023-04-10 14:00:00', 'Revisión posquirúrgica', 'Completada', 'Evolución favorable'),
(5, 5, 4, '2023-04-10 15:00:00', 'Limpieza dental', 'Completada', 'Requiere anestesia'),
(6, 6, 5, '2023-04-10 16:00:00', 'Problemas de piel', 'Completada', 'Presenta descamación y picazón'),
(7, 7, 1, '2023-04-11 09:00:00', 'Vacunación', 'Programada', NULL),
(8, 8, 2, '2023-04-11 10:00:00', 'Problemas respiratorios', 'Programada', 'Dificultad para respirar'),
(9, 9, 3, '2023-04-11 11:00:00', 'Consulta de rutina', 'Programada', NULL),
(10, 10, 4, '2023-04-11 14:00:00', 'Problemas de movilidad', 'Programada', 'Cojera en pata trasera derecha');

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `detalle_facturas`
--

CREATE TABLE `detalle_facturas` (
  `id_detalle` int(11) NOT NULL,
  `id_factura` int(11) NOT NULL,
  `id_cita` int(11) DEFAULT NULL,
  `id_tratamiento` int(11) DEFAULT NULL,
  `cantidad` int(11) NOT NULL,
  `precio_unitario` decimal(10,2) NOT NULL,
  `descuento` decimal(10,2) DEFAULT 0.00,
  `subtotal` decimal(10,2) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Volcado de datos para la tabla `detalle_facturas`
--

INSERT INTO `detalle_facturas` (`id_detalle`, `id_factura`, `id_cita`, `id_tratamiento`, `cantidad`, `precio_unitario`, `descuento`, `subtotal`) VALUES
(1, 1, 1, NULL, 1, 50000.00, 0.00, 50000.00),
(2, 2, 2, 1, 1, 50000.00, 0.00, 50000.00),
(3, 3, 3, 6, 1, 60000.00, 0.00, 60000.00),
(4, 3, 3, NULL, 1, 60000.00, 0.00, 60000.00),
(5, 5, 5, 5, 1, 100000.00, 0.00, 100000.00),
(6, 6, 6, 8, 1, 65000.00, 0.00, 65000.00),
(7, 6, 6, NULL, 1, 60000.00, 0.00, 60000.00);

--
-- Disparadores `detalle_facturas`
--
DELIMITER $$
CREATE TRIGGER `validar_facturacion_cita` BEFORE INSERT ON `detalle_facturas` FOR EACH ROW BEGIN
    DECLARE v_tiene_evolucion BOOLEAN DEFAULT FALSE;
    DECLARE v_tiene_diagnostico BOOLEAN DEFAULT FALSE;
    DECLARE v_tiene_tratamiento BOOLEAN DEFAULT FALSE;
    DECLARE v_id_mascota INT;
    DECLARE v_id_veterinario INT;

    -- Solo validar si hay una cita asociada
    IF NEW.id_cita IS NOT NULL THEN
        -- Verificar si existe historia clínica con evolución
        SELECT COUNT(*) > 0, hc.id_mascota, hc.id_veterinario
        INTO v_tiene_evolucion, v_id_mascota, v_id_veterinario
        FROM historias_clinicas hc
        WHERE hc.id_cita = NEW.id_cita
        AND hc.evolucion IS NOT NULL
        AND TRIM(hc.evolucion) != ''
        GROUP BY hc.id_mascota, hc.id_veterinario;

        -- Verificar si tiene diagnóstico
        SELECT COUNT(*) > 0 INTO v_tiene_diagnostico
        FROM historias_clinicas hc
        WHERE hc.id_cita = NEW.id_cita
        AND hc.id_diagnostico IS NOT NULL;

        -- Verificar si tiene tratamiento registrado
        SELECT COUNT(*) > 0 INTO v_tiene_tratamiento
        FROM tratamientos_aplicados ta
        INNER JOIN historias_clinicas hc ON ta.id_historia_clinica = hc.id_historia_clinica
        WHERE hc.id_cita = NEW.id_cita;

        -- Validar las condiciones
        IF NOT v_tiene_evolucion THEN
            -- Registrar el intento fallido
            INSERT INTO registro_errores_clinicos (
                tipo_error,
                descripcion,
                id_mascota,
                id_veterinario,
                fecha_hora,
                usuario
            )
            VALUES (
                'Facturación sin evolución clínica',
                CONCAT('Intento de facturar cita ID: ', NEW.id_cita, ' sin evolución clínica registrada'),
                v_id_mascota,
                v_id_veterinario,
                NOW(),
                USER()
            );

            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Error: No se puede facturar sin evolución clínica registrada';

        ELSEIF NOT v_tiene_diagnostico THEN
            -- Registrar el intento fallido
            INSERT INTO registro_errores_clinicos (
                tipo_error,
                descripcion,
                id_mascota,
                id_veterinario,
                fecha_hora,
                usuario
            )
            VALUES (
                'Facturación sin diagnóstico',
                CONCAT('Intento de facturar cita ID: ', NEW.id_cita, ' sin diagnóstico registrado'),
                v_id_mascota,
                v_id_veterinario,
                NOW(),
                USER()
            );

            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Error: No se puede facturar sin diagnóstico registrado';

        ELSEIF NOT v_tiene_tratamiento THEN
            -- Registrar el intento fallido
            INSERT INTO registro_errores_clinicos (
                tipo_error,
                descripcion,
                id_mascota,
                id_veterinario,
                fecha_hora,
                usuario
            )
            VALUES (
                'Facturación sin tratamiento',
                CONCAT('Intento de facturar cita ID: ', NEW.id_cita, ' sin tratamiento aplicado'),
                v_id_mascota,
                v_id_veterinario,
                NOW(),
                USER()
            );

            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Error: No se puede facturar sin tratamiento registrado';
        END IF;
    END IF;
END
$$
DELIMITER ;

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `diagnosticos`
--

CREATE TABLE `diagnosticos` (
  `id_diagnostico` int(11) NOT NULL,
  `nombre` varchar(100) NOT NULL,
  `descripcion` text DEFAULT NULL,
  `categoria` varchar(50) DEFAULT NULL,
  `riesgo_vital` tinyint(1) DEFAULT 0
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Volcado de datos para la tabla `diagnosticos`
--

INSERT INTO `diagnosticos` (`id_diagnostico`, `nombre`, `descripcion`, `categoria`, `riesgo_vital`) VALUES
(1, 'Infección respiratoria', 'Infección en vías respiratorias altas o bajas', 'Respiratorio', 0),
(2, 'Gastroenteritis', 'Inflamación del tracto gastrointestinal', 'Digestivo', 0),
(3, 'Otitis', 'Inflamación del oído', 'Dermatológico', 0),
(4, 'Dermatitis alérgica', 'Reacción alérgica cutánea', 'Dermatológico', 0),
(5, 'Fractura ósea', 'Ruptura de hueso', 'Traumatológico', 0),
(6, 'Pancreatitis', 'Inflamación del páncreas', 'Digestivo', 1),
(7, 'Parvovirus', 'Infección viral altamente contagiosa', 'Infeccioso', 1),
(8, 'Insuficiencia renal', 'Deterioro de la función renal', 'Renal', 1),
(9, 'Diabetes mellitus', 'Trastorno metabólico', 'Endocrino', 0),
(10, 'Parasitosis intestinal', 'Infestación por parásitos intestinales', 'Digestivo', 0);

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `especies`
--

CREATE TABLE `especies` (
  `id_especie` int(11) NOT NULL,
  `nombre` varchar(50) NOT NULL,
  `descripcion` text DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Volcado de datos para la tabla `especies`
--

INSERT INTO `especies` (`id_especie`, `nombre`, `descripcion`) VALUES
(1, 'Perro', 'Canino doméstico, mamífero carnívoro de la familia de los cánidos'),
(2, 'Gato', 'Felino doméstico, mamífero carnívoro de la familia de los félidos'),
(3, 'Ave', 'Animales vertebrados de sangre caliente caracterizados por tener plumas'),
(4, 'Reptil', 'Animales vertebrados de sangre fría cubiertos de escamas'),
(5, 'Roedor', 'Mamíferos caracterizados por sus dientes incisivos');

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `eventos_criticos`
--

CREATE TABLE `eventos_criticos` (
  `id_evento` int(11) NOT NULL,
  `id_mascota` int(11) NOT NULL,
  `id_historia_clinica` int(11) NOT NULL,
  `id_diagnostico` int(11) NOT NULL,
  `fecha_hora` datetime NOT NULL,
  `descripcion` text DEFAULT NULL,
  `estado` enum('Activo','Resuelto') DEFAULT 'Activo',
  `fecha_resolucion` datetime DEFAULT NULL,
  `notificado_a` int(11) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Volcado de datos para la tabla `eventos_criticos`
--

INSERT INTO `eventos_criticos` (`id_evento`, `id_mascota`, `id_historia_clinica`, `id_diagnostico`, `fecha_hora`, `descripcion`, `estado`, `fecha_resolucion`, `notificado_a`) VALUES
(1, 3, 3, 2, '2023-04-10 11:35:00', 'Gastroenteritis severa con deshidratación', 'Resuelto', '2023-04-12 09:00:00', 3);

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `facturas`
--

CREATE TABLE `facturas` (
  `id_factura` int(11) NOT NULL,
  `id_propietario` int(11) NOT NULL,
  `fecha_emision` datetime NOT NULL,
  `total` decimal(10,2) NOT NULL,
  `estado` enum('Pendiente','Pagada','Anulada') DEFAULT 'Pendiente',
  `metodo_pago` varchar(50) DEFAULT NULL,
  `observaciones` text DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Volcado de datos para la tabla `facturas`
--

INSERT INTO `facturas` (`id_factura`, `id_propietario`, `fecha_emision`, `total`, `estado`, `metodo_pago`, `observaciones`) VALUES
(1, 1, '2023-04-10 10:00:00', 50000.00, 'Pagada', 'Efectivo', 'Revisión anual'),
(2, 2, '2023-04-10 11:00:00', 50000.00, 'Pagada', 'Tarjeta', 'Vacunación antirrábica'),
(3, 3, '2023-04-10 12:00:00', 120000.00, 'Pagada', 'Transferencia', 'Consulta y tratamiento gastroenteritis'),
(4, 4, '2023-04-10 15:00:00', 0.00, 'Anulada', NULL, 'Factura anulada por error'),
(5, 5, '2023-04-10 16:00:00', 100000.00, 'Pagada', 'Efectivo', 'Limpieza dental'),
(6, 6, '2023-04-10 17:00:00', 125000.00, 'Pendiente', NULL, 'Consulta dermatológica y medicamentos');

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `historias_clinicas`
--

CREATE TABLE `historias_clinicas` (
  `id_historia_clinica` int(11) NOT NULL,
  `id_cita` int(11) NOT NULL,
  `id_mascota` int(11) NOT NULL,
  `id_veterinario` int(11) NOT NULL,
  `id_diagnostico` int(11) DEFAULT NULL,
  `fecha` datetime NOT NULL,
  `anamnesis` text DEFAULT NULL,
  `exploracion` text DEFAULT NULL,
  `estado_general` varchar(255) DEFAULT NULL,
  `temperatura` decimal(3,1) DEFAULT NULL,
  `peso` decimal(5,2) DEFAULT NULL,
  `evolucion` text DEFAULT NULL,
  `tiene_alta` tinyint(1) DEFAULT 0,
  `fecha_alta` datetime DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Volcado de datos para la tabla `historias_clinicas`
--

INSERT INTO `historias_clinicas` (`id_historia_clinica`, `id_cita`, `id_mascota`, `id_veterinario`, `id_diagnostico`, `fecha`, `anamnesis`, `exploracion`, `estado_general`, `temperatura`, `peso`, `evolucion`, `tiene_alta`, `fecha_alta`) VALUES
(1, 1, 1, 1, NULL, '2023-04-10 09:30:00', 'Revisión anual, sin síntomas previos', 'Exploración completa sin hallazgos relevantes', 'Bueno', 38.5, 28.50, 'Mascota en perfecto estado de salud', 1, NULL),
(2, 2, 2, 1, NULL, '2023-04-10 10:30:00', 'Vacunación programada', 'Sin hallazgos patológicos', 'Bueno', 38.7, 32.00, 'Se administra vacuna antirrábica sin complicaciones', 1, NULL),
(3, 3, 3, 2, 2, '2023-04-10 11:30:00', 'Vómitos desde hace 2 días, inapetencia', 'Abdomen blando pero doloroso a la palpación', 'Regular', 39.2, 4.30, 'Se diagnostica gastroenteritis leve, se prescribe tratamiento', 1, NULL),
(4, 4, 4, 3, NULL, '2023-04-10 14:30:00', 'Revisión tras cirugía de extracción de cuerpo extraño', 'Herida quirúrgica con buena cicatrización, sin signos de infección', 'Bueno', 38.5, 6.20, 'Evolución favorable, se retiran puntos', 1, NULL),
(5, 5, 5, 4, 3, '2023-04-10 15:30:00', 'Problemas de higiene dental', 'Presencia de sarro y gingivitis leve', 'Bueno', 38.2, 1.80, 'Se realiza limpieza dental bajo anestesia sin complicaciones', 1, NULL),
(6, 6, 6, 5, 4, '2023-04-10 16:30:00', 'Picazón y zonas de pelo perdido', 'Áreas de alopecia y eritema en zona dorsal', 'Bueno', 38.6, 30.50, 'Se diagnostica dermatitis alérgica, se prescribe tratamiento', 1, NULL);

--
-- Disparadores `historias_clinicas`
--
DELIMITER $$
CREATE TRIGGER `registrar_diagnostico_critico_insert` AFTER INSERT ON `historias_clinicas` FOR EACH ROW BEGIN
    DECLARE v_es_riesgo_vital BOOLEAN DEFAULT FALSE;
    DECLARE v_nombre_diagnostico VARCHAR(100);
    DECLARE v_id_director INT;

    -- Verificar si el diagnóstico es de riesgo vital
    IF NEW.id_diagnostico IS NOT NULL THEN
        SELECT d.riesgo_vital, d.nombre
        INTO v_es_riesgo_vital, v_nombre_diagnostico
        FROM diagnosticos d
        WHERE d.id_diagnostico = NEW.id_diagnostico;

        IF v_es_riesgo_vital THEN
            -- Obtener ID del director médico
            SELECT v.id_veterinario INTO v_id_director
            FROM veterinarios v
            INNER JOIN cargos c ON v.id_cargo = c.id_cargo
            WHERE c.nombre = 'Director Médico'
            AND v.activo = TRUE
            LIMIT 1;

            -- Registrar evento crítico
            INSERT INTO eventos_criticos (
                id_mascota,
                id_historia_clinica,
                id_diagnostico,
                fecha_hora,
                descripcion,
                estado,
                notificado_a
            )
            VALUES (
                NEW.id_mascota,
                NEW.id_historia_clinica,
                NEW.id_diagnostico,
                NOW(),
                CONCAT('Diagnóstico de riesgo vital: ', v_nombre_diagnostico),
                'Activo',
                v_id_director
            );

            -- Notificar al director médico
            INSERT INTO notificaciones_administrativas (
                tipo_notificacion,
                mensaje,
                dirigido_a,
                fecha_hora,
                leida
            )
            VALUES (
                'Evento Crítico',
                CONCAT('ALERTA: Diagnóstico de riesgo vital para mascota ID: ', NEW.id_mascota,
                       '. Diagnóstico: ', v_nombre_diagnostico,
                       '. La mascota no puede ser dada de alta sin autorización médica.'),
                'Director Médico',
                NOW(),
                FALSE
            );

            -- Actualizar historia clínica para bloquear alta
            UPDATE historias_clinicas
            SET tiene_alta = FALSE
            WHERE id_historia_clinica = NEW.id_historia_clinica;
        END IF;
    END IF;
END
$$
DELIMITER ;
DELIMITER $$
CREATE TRIGGER `registrar_diagnostico_critico_update` AFTER UPDATE ON `historias_clinicas` FOR EACH ROW BEGIN
    DECLARE v_es_riesgo_vital BOOLEAN DEFAULT FALSE;
    DECLARE v_nombre_diagnostico VARCHAR(100);
    DECLARE v_id_director INT;

    -- Solo procesar si el diagnóstico cambió
    IF NEW.id_diagnostico != OLD.id_diagnostico OR
       (OLD.id_diagnostico IS NULL AND NEW.id_diagnostico IS NOT NULL) THEN

        -- Verificar si el nuevo diagnóstico es de riesgo vital
        IF NEW.id_diagnostico IS NOT NULL THEN
            SELECT d.riesgo_vital, d.nombre
            INTO v_es_riesgo_vital, v_nombre_diagnostico
            FROM diagnosticos d
            WHERE d.id_diagnostico = NEW.id_diagnostico;

            IF v_es_riesgo_vital THEN
                -- Obtener ID del director médico
                SELECT v.id_veterinario INTO v_id_director
                FROM veterinarios v
                INNER JOIN cargos c ON v.id_cargo = c.id_cargo
                WHERE c.nombre = 'Director Médico'
                AND v.activo = TRUE
                LIMIT 1;

                -- Registrar evento crítico
                INSERT INTO eventos_criticos (
                    id_mascota,
                    id_historia_clinica,
                    id_diagnostico,
                    fecha_hora,
                    descripcion,
                    estado,
                    notificado_a
                )
                VALUES (
                    NEW.id_mascota,
                    NEW.id_historia_clinica,
                    NEW.id_diagnostico,
                    NOW(),
                    CONCAT('Diagnóstico de riesgo vital actualizado: ', v_nombre_diagnostico),
                    'Activo',
                    v_id_director
                );

                -- Notificar al director médico
                INSERT INTO notificaciones_administrativas (
                    tipo_notificacion,
                    mensaje,
                    dirigido_a,
                    fecha_hora,
                    leida
                )
                VALUES (
                    'Evento Crítico',
                    CONCAT('ALERTA: Diagnóstico de riesgo vital actualizado para mascota ID: ', NEW.id_mascota,
                           '. Nuevo diagnóstico: ', v_nombre_diagnostico,
                           '. La mascota requiere supervisión especial.'),
                    'Director Médico',
                    NOW(),
                    FALSE
                );

                -- Asegurar que el alta esté bloqueada
                UPDATE historias_clinicas
                SET tiene_alta = FALSE
                WHERE id_historia_clinica = NEW.id_historia_clinica;
            END IF;
        END IF;
    END IF;
END
$$
DELIMITER ;

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `inventario_medicamentos`
--

CREATE TABLE `inventario_medicamentos` (
  `id_inventario` int(11) NOT NULL,
  `id_medicamento` int(11) NOT NULL,
  `cantidad` int(11) NOT NULL,
  `nivel_minimo` int(11) NOT NULL,
  `nivel_optimo` int(11) NOT NULL,
  `ubicacion` varchar(100) DEFAULT NULL,
  `fecha_actualizacion` datetime DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Volcado de datos para la tabla `inventario_medicamentos`
--

INSERT INTO `inventario_medicamentos` (`id_inventario`, `id_medicamento`, `cantidad`, `nivel_minimo`, `nivel_optimo`, `ubicacion`, `fecha_actualizacion`) VALUES
(1, 1, 10, 50, 200, 'Estante A-1', '2025-05-14 20:04:49'),
(2, 2, 120, 40, 150, 'Estante A-2', '2023-04-01 08:10:00'),
(3, 3, 80, 30, 100, 'Estante A-3', '2023-04-01 08:20:00'),
(4, 4, 100, 30, 120, 'Estante B-1', '2023-04-01 08:30:00'),
(5, 5, 60, 50, 100, 'Estante B-2', '2023-04-01 08:40:00'),
(6, 6, 60, 20, 80, 'Estante B-3', '2023-04-01 08:50:00'),
(7, 7, 90, 30, 100, 'Estante C-1', '2023-04-01 09:00:00'),
(8, 8, 50, 30, 80, 'Estante C-2', '2025-05-14 19:53:48'),
(9, 9, 5, 10, 30, 'Refrigerador 1', '2025-05-21 18:08:35'),
(10, 10, 70, 30, 90, 'Estante C-3', '2023-04-01 09:30:00');

--
-- Disparadores `inventario_medicamentos`
--
DELIMITER $$
CREATE TRIGGER `solicitar_reabastecimiento_automatico` AFTER UPDATE ON `inventario_medicamentos` FOR EACH ROW BEGIN
    DECLARE v_nombre_medicamento VARCHAR(100);
    DECLARE v_id_jefe_clinico INT;

    -- Verificar si se alcanzó el nivel mínimo (y antes no estaba en nivel mínimo)
    IF NEW.cantidad <= NEW.nivel_minimo AND OLD.cantidad > OLD.nivel_minimo THEN
        -- Obtener el nombre del medicamento
        SELECT nombre INTO v_nombre_medicamento
        FROM medicamentos
        WHERE id_medicamento = NEW.id_medicamento;

        -- Obtener el ID del jefe clínico
        SELECT v.id_veterinario INTO v_id_jefe_clinico
        FROM veterinarios v
        INNER JOIN cargos c ON v.id_cargo = c.id_cargo
        WHERE c.nombre = 'Jefe Clínico'
        AND v.activo = TRUE
        LIMIT 1;

        -- a) Crear solicitud de aprobación
        INSERT INTO solicitudes_reabastecimiento (
            id_medicamento,
            cantidad_actual,
            cantidad_solicitada,
            estado,
            fecha_solicitud,
            id_jefe_clinico,
            observaciones
        )
        VALUES (
            NEW.id_medicamento,
            NEW.cantidad,
            NEW.nivel_optimo - NEW.cantidad,
            'Pendiente',
            NOW(),
            NULL, -- Se asignará cuando el jefe clínico responda
            CONCAT('Solicitud automática. Nivel mínimo alcanzado: ', NEW.nivel_minimo)
        );

        -- b) Notificar mediante tabla de notificaciones
        INSERT INTO notificaciones_administrativas (
            tipo_notificacion,
            mensaje,
            dirigido_a,
            fecha_hora,
            leida
        )
        VALUES (
            'Reabastecimiento',
            CONCAT('URGENTE: El medicamento ', v_nombre_medicamento,
                   ' (ID: ', NEW.id_medicamento, ') ha alcanzado su nivel mínimo. ',
                   'Cantidad actual: ', NEW.cantidad, '. Se requiere aprobación de reabastecimiento.'),
            'Jefe Clínico',
            NOW(),
            FALSE
        );

        -- c) El registro del evento ya está implícito en las dos inserciones anteriores
        -- con fecha y hora NOW()
    END IF;
END
$$
DELIMITER ;

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `mascotas`
--

CREATE TABLE `mascotas` (
  `id_mascota` int(11) NOT NULL,
  `id_propietario` int(11) NOT NULL,
  `id_especie` int(11) NOT NULL,
  `id_raza` int(11) NOT NULL,
  `nombre` varchar(50) NOT NULL,
  `fecha_nacimiento` date DEFAULT NULL,
  `sexo` enum('Macho','Hembra') NOT NULL,
  `color` varchar(50) DEFAULT NULL,
  `peso` decimal(5,2) DEFAULT NULL,
  `activo` tinyint(1) DEFAULT 1,
  `fecha_registro` date NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Volcado de datos para la tabla `mascotas`
--

INSERT INTO `mascotas` (`id_mascota`, `id_propietario`, `id_especie`, `id_raza`, `nombre`, `fecha_nacimiento`, `sexo`, `color`, `peso`, `activo`, `fecha_registro`) VALUES
(1, 1, 1, 1, 'Max', '2019-05-15', 'Macho', 'Negro', 28.50, 1, '2020-01-15'),
(2, 2, 1, 3, 'Luna', '2018-07-20', 'Hembra', 'Marrón y Negro', 32.00, 1, '2020-02-20'),
(3, 3, 2, 6, 'Michi', '2019-03-10', 'Macho', 'Blanco', 4.50, 1, '2020-03-10'),
(4, 4, 2, 8, 'Felix', '2018-11-05', 'Macho', 'Atigrado', 6.20, 1, '2020-04-05'),
(5, 5, 1, 4, 'Tiny', '2019-09-12', 'Hembra', 'Marrón', 1.80, 1, '2020-05-12'),
(6, 6, 1, 5, 'Rocky', '2020-01-30', 'Macho', 'Dorado', 30.50, 1, '2021-01-30'),
(7, 7, 2, 7, 'Simba', '2019-12-15', 'Macho', 'Atigrado', 8.00, 1, '2021-02-15'),
(8, 8, 3, 11, 'Piolín', '2020-03-20', 'Macho', 'Amarillo', 0.10, 1, '2021-03-20'),
(9, 9, 4, 15, 'Rex', '2019-10-10', 'Macho', 'Verde', 2.50, 1, '2021-04-10'),
(10, 10, 5, 19, 'Bolita', '2020-05-05', 'Hembra', 'Blanco y Marrón', 0.30, 1, '2021-05-05');

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `medicamentos`
--

CREATE TABLE `medicamentos` (
  `id_medicamento` int(11) NOT NULL,
  `nombre` varchar(100) NOT NULL,
  `composicion` text DEFAULT NULL,
  `dosis_recomendada` varchar(100) DEFAULT NULL,
  `via_administracion` varchar(50) DEFAULT NULL,
  `contraindicaciones` text DEFAULT NULL,
  `precio_unitario` decimal(10,2) NOT NULL,
  `lote` varchar(50) DEFAULT NULL,
  `fecha_vencimiento` date DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Volcado de datos para la tabla `medicamentos`
--

INSERT INTO `medicamentos` (`id_medicamento`, `nombre`, `composicion`, `dosis_recomendada`, `via_administracion`, `contraindicaciones`, `precio_unitario`, `lote`, `fecha_vencimiento`) VALUES
(1, 'Amoxicilina 250mg', 'Amoxicilina trihidrato', '10-20 mg/kg cada 12h', 'Oral', 'Hipersensibilidad a penicilinas', 15000.00, 'AMX-25689', '2024-06-30'),
(2, 'Metronidazol 500mg', 'Metronidazol', '10-15 mg/kg cada 12h', 'Oral', 'Insuficiencia hepática severa', 18000.00, 'MTZ-34567', '2024-08-15'),
(3, 'Ivermectina gotas', 'Ivermectina 0.1%', '0.2-0.4 mg/kg', 'Tópica', 'No usar en Collies y razas relacionadas', 25000.00, 'IVM-45678', '2024-05-20'),
(4, 'Prednisolona 20mg', 'Prednisolona', '0.5-1 mg/kg cada 12-24h', 'Oral', 'Tuberculosis, micosis sistémica', 12000.00, 'PRD-56789', '2024-07-10'),
(5, 'Suero Fisiológico 500ml', 'Cloruro de sodio 0.9%', 'Según necesidad', 'Intravenosa', 'No usar en casos de hipernatremia', 8000.00, 'SF-67890', '2025-01-15'),
(6, 'Ceftriaxona 1g', 'Ceftriaxona sódica', '25-50 mg/kg cada 24h', 'Intramuscular', 'Hipersensibilidad a cefalosporinas', 30000.00, 'CFX-78901', '2024-09-30'),
(7, 'Tramadol 50mg', 'Hidrocloruro de tramadol', '2-4 mg/kg cada 8-12h', 'Oral', 'Pacientes tratados con IMAO', 22000.00, 'TRM-89012', '2024-04-30'),
(8, 'Furosemida 40mg', 'Furosemida', '2-4 mg/kg cada 8-12h', 'Oral o inyectable', 'Deshidratación severa', 14000.00, 'FRS-90123', '2024-10-15'),
(9, 'Insulina NPH', 'Insulina humana isofánica', 'Según glucemia', 'Subcutánea', 'Hipoglucemia', 40000.00, 'INS-01234', '2024-03-30'),
(10, 'Meloxicam 2mg', 'Meloxicam', '0.1-0.2 mg/kg cada 24h', 'Oral', 'Insuficiencia renal o hepática severa', 16000.00, 'MLX-12345', '2024-08-30');

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `notificaciones_administrativas`
--

CREATE TABLE `notificaciones_administrativas` (
  `id_notificacion` int(11) NOT NULL,
  `tipo_notificacion` varchar(50) NOT NULL,
  `mensaje` text NOT NULL,
  `dirigido_a` varchar(100) NOT NULL,
  `fecha_hora` datetime NOT NULL,
  `leida` tinyint(1) DEFAULT 0,
  `fecha_lectura` datetime DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Volcado de datos para la tabla `notificaciones_administrativas`
--

INSERT INTO `notificaciones_administrativas` (`id_notificacion`, `tipo_notificacion`, `mensaje`, `dirigido_a`, `fecha_hora`, `leida`, `fecha_lectura`) VALUES
(1, 'Reabastecimiento', 'Nivel crítico de Suero Fisiológico (ID: 5)', 'Jefe Clínico', '2023-04-01 10:00:00', 1, '2023-04-01 10:30:00'),
(2, 'Reabastecimiento', 'Nivel crítico de Furosemida (ID: 8)', 'Jefe Clínico', '2023-04-02 11:15:00', 1, '2023-04-02 11:45:00'),
(3, 'Evento Crítico', 'Diagnóstico de riesgo vital para mascota ID: 3', 'Director Médico', '2023-04-03 09:30:00', 1, '2023-04-03 09:45:00'),
(4, 'Reabastecimiento', 'URGENTE: El medicamento Amoxicilina 250mg (ID: 1) ha alcanzado su nivel mínimo. Cantidad actual: 50. Se requiere aprobación de reabastecimiento.', 'Jefe Clínico', '2025-05-14 19:54:09', 0, NULL),
(5, 'Reabastecimiento', 'URGENTE: El medicamento Amoxicilina 250mg (ID: 1) ha alcanzado su nivel mínimo. Cantidad actual: 10. Se requiere aprobación de reabastecimiento.', 'Jefe Clínico', '2025-05-14 20:04:49', 0, NULL),
(6, 'Reabastecimiento', 'URGENTE: El medicamento Insulina NPH (ID: 9) ha alcanzado su nivel mínimo. Cantidad actual: 5. Se requiere aprobación de reabastecimiento.', 'Jefe Clínico', '2025-05-21 18:08:35', 0, NULL);

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `propietarios`
--

CREATE TABLE `propietarios` (
  `id_propietario` int(11) NOT NULL,
  `nombre` varchar(100) NOT NULL,
  `apellido` varchar(100) NOT NULL,
  `telefono` varchar(20) NOT NULL,
  `email` varchar(100) DEFAULT NULL,
  `direccion` varchar(255) DEFAULT NULL,
  `fecha_registro` date NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Volcado de datos para la tabla `propietarios`
--

INSERT INTO `propietarios` (`id_propietario`, `nombre`, `apellido`, `telefono`, `email`, `direccion`, `fecha_registro`) VALUES
(1, 'Carlos', 'Gómez', '3001234567', 'carlos.gomez@email.com', 'Calle 123 #45-67', '2020-01-15'),
(2, 'María', 'López', '3109876543', 'maria.lopez@email.com', 'Avenida 45 #23-56', '2020-02-20'),
(3, 'Juan', 'Martínez', '3201234567', 'juan.martinez@email.com', 'Carrera 67 #12-34', '2020-03-10'),
(4, 'Ana', 'Rodríguez', '3501234567', 'ana.rodriguez@email.com', 'Diagonal 23 #45-67', '2020-04-05'),
(5, 'Pedro', 'Sánchez', '3157654321', 'pedro.sanchez@email.com', 'Calle 56 #78-90', '2020-05-12'),
(6, 'Laura', 'Hernández', '3002345678', 'laura.hernandez@email.com', 'Avenida 78 #45-23', '2021-01-30'),
(7, 'Roberto', 'Díaz', '3113456789', 'roberto.diaz@email.com', 'Carrera 34 #56-78', '2021-02-15'),
(8, 'Sofía', 'García', '3204567890', 'sofia.garcia@email.com', 'Diagonal 56 #78-90', '2021-03-20'),
(9, 'Daniel', 'Pérez', '3506789012', 'daniel.perez@email.com', 'Calle 89 #12-34', '2021-04-10'),
(10, 'Carmen', 'Ramírez', '3158901234', 'carmen.ramirez@email.com', 'Avenida 12 #34-56', '2021-05-05');

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `razas`
--

CREATE TABLE `razas` (
  `id_raza` int(11) NOT NULL,
  `id_especie` int(11) NOT NULL,
  `nombre` varchar(50) NOT NULL,
  `tamano` enum('Pequeño','Mediano','Grande') NOT NULL,
  `caracteristicas` text DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Volcado de datos para la tabla `razas`
--

INSERT INTO `razas` (`id_raza`, `id_especie`, `nombre`, `tamano`, `caracteristicas`) VALUES
(1, 1, 'Labrador Retriever', 'Grande', 'Amistoso, activo, buen carácter familiar'),
(2, 1, 'Bulldog', 'Mediano', 'Tranquilo, amigable, cabezón y arrugado'),
(3, 1, 'Pastor Alemán', 'Grande', 'Inteligente, versátil, leal, buen guardián'),
(4, 1, 'Chihuahua', 'Pequeño', 'Pequeño pero de gran personalidad, alerta'),
(5, 1, 'Golden Retriever', 'Grande', 'Inteligente, amable, confiable y fiel'),
(6, 2, 'Persa', 'Mediano', 'Pelo largo, cara plana, tranquilo'),
(7, 2, 'Siamés', 'Mediano', 'Elegante, hablador, inteligente, sociable'),
(8, 2, 'Maine Coon', 'Grande', 'El gato doméstico más grande, peludo, amigable'),
(9, 2, 'Sphynx', 'Mediano', 'Sin pelo, cariñoso, juguetón'),
(10, 2, 'Bengali', 'Mediano', 'Manchas de leopardo, activo, enérgico'),
(11, 3, 'Canario', 'Pequeño', 'Ave cantora, diversidad de colores'),
(12, 3, 'Periquito', 'Pequeño', 'Sociable, inteligente, juguetón'),
(13, 3, 'Agapornis', 'Pequeño', 'Conocido como inseparable, afectuoso, colorido'),
(14, 3, 'Loro Gris Africano', 'Mediano', 'Inteligente, capaz de imitar sonidos y palabras'),
(15, 4, 'Iguana Verde', 'Grande', 'Herbívoro, necesita espacios grandes'),
(16, 4, 'Gecko Leopardo', 'Pequeño', 'Dócil, fácil de cuidar, nocturno'),
(17, 4, 'Tortuga de Tierra', 'Mediano', 'Longeva, herbívora, tranquila'),
(18, 5, 'Hámster Sirio', 'Pequeño', 'Solitario, nocturno, territorial'),
(19, 5, 'Conejo Enano', 'Pequeño', 'Social, limpio, puede entrenarse'),
(20, 5, 'Cobaya o Cuy', 'Pequeño', 'Social, vocal, requiere vitamina C');

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `registro_errores_clinicos`
--

CREATE TABLE `registro_errores_clinicos` (
  `id_error` int(11) NOT NULL,
  `tipo_error` varchar(100) NOT NULL,
  `descripcion` text DEFAULT NULL,
  `id_mascota` int(11) DEFAULT NULL,
  `id_tratamiento` int(11) DEFAULT NULL,
  `id_veterinario` int(11) DEFAULT NULL,
  `fecha_hora` datetime NOT NULL,
  `usuario` varchar(100) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Volcado de datos para la tabla `registro_errores_clinicos`
--

INSERT INTO `registro_errores_clinicos` (`id_error`, `tipo_error`, `descripcion`, `id_mascota`, `id_tratamiento`, `id_veterinario`, `fecha_hora`, `usuario`) VALUES
(1, 'Tratamiento incompatible', 'Intento de aplicar tratamiento no compatible con la especie', 8, 5, 2, '2023-04-09 14:30:00', 'valentina.gutierrez'),
(2, 'Medicamento caducado', 'Intento de utilizar medicamento con fecha de vencimiento pasada', 4, 6, 3, '2023-04-08 11:20:00', 'ricardo.mendoza'),
(3, 'Dosis incorrecta', 'Cálculo erróneo de dosis de medicamento', 2, 6, 1, '2023-04-07 16:45:00', 'alejandro.ramirez');

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `solicitudes_reabastecimiento`
--

CREATE TABLE `solicitudes_reabastecimiento` (
  `id_solicitud` int(11) NOT NULL,
  `id_medicamento` int(11) NOT NULL,
  `cantidad_actual` int(11) NOT NULL,
  `cantidad_solicitada` int(11) NOT NULL,
  `estado` enum('Pendiente','Aprobada','Rechazada') DEFAULT 'Pendiente',
  `fecha_solicitud` datetime NOT NULL,
  `fecha_respuesta` datetime DEFAULT NULL,
  `id_jefe_clinico` int(11) DEFAULT NULL,
  `observaciones` text DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Volcado de datos para la tabla `solicitudes_reabastecimiento`
--

INSERT INTO `solicitudes_reabastecimiento` (`id_solicitud`, `id_medicamento`, `cantidad_actual`, `cantidad_solicitada`, `estado`, `fecha_solicitud`, `fecha_respuesta`, `id_jefe_clinico`, `observaciones`) VALUES
(1, 5, 45, 55, 'Aprobada', '2023-04-01 10:00:00', '2023-04-01 10:30:00', 2, 'Aprobada para reabastecimiento inmediato'),
(2, 8, 25, 55, 'Aprobada', '2023-04-02 11:15:00', '2023-04-02 11:45:00', 2, 'Aprobada para reabastecimiento inmediato'),
(3, 9, 15, 15, 'Pendiente', '2023-04-03 14:20:00', NULL, NULL, NULL),
(4, 1, 50, 150, 'Pendiente', '2025-05-14 19:54:09', NULL, NULL, 'Solicitud automática. Nivel mínimo alcanzado: 50'),
(5, 1, 10, 190, 'Pendiente', '2025-05-14 20:04:49', NULL, NULL, 'Solicitud automática. Nivel mínimo alcanzado: 50'),
(6, 9, 5, 25, 'Pendiente', '2025-05-21 18:08:35', NULL, NULL, 'Solicitud automática. Nivel mínimo alcanzado: 10');

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `tratamientos`
--

CREATE TABLE `tratamientos` (
  `id_tratamiento` int(11) NOT NULL,
  `nombre` varchar(100) NOT NULL,
  `descripcion` text DEFAULT NULL,
  `tipo` varchar(50) DEFAULT NULL,
  `precio` decimal(10,2) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Volcado de datos para la tabla `tratamientos`
--

INSERT INTO `tratamientos` (`id_tratamiento`, `nombre`, `descripcion`, `tipo`, `precio`) VALUES
(1, 'Vacunación antirrábica', 'Inmunización contra el virus de la rabia', 'Preventivo', 50000.00),
(2, 'Vacunación polivalente', 'Inmunización contra múltiples patógenos', 'Preventivo', 70000.00),
(3, 'Desparasitación interna', 'Eliminación de parásitos intestinales', 'Preventivo', 40000.00),
(4, 'Desparasitación externa', 'Eliminación de parásitos externos', 'Preventivo', 45000.00),
(5, 'Limpieza dental', 'Eliminación de sarro y pulido dental', 'Higiene', 100000.00),
(6, 'Tratamiento antibiótico', 'Administración de antibióticos para combatir infecciones', 'Terapéutico', 60000.00),
(7, 'Terapia con fluidos', 'Administración de fluidos intravenosos', 'Terapéutico', 80000.00),
(8, 'Tratamiento dermatológico', 'Tratamiento para problemas de piel', 'Terapéutico', 65000.00),
(9, 'Cirugía menor', 'Procedimientos quirúrgicos menores', 'Quirúrgico', 150000.00),
(10, 'Cirugía mayor', 'Procedimientos quirúrgicos complejos', 'Quirúrgico', 300000.00);

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `tratamientos_aplicados`
--

CREATE TABLE `tratamientos_aplicados` (
  `id_tratamiento_aplicado` int(11) NOT NULL,
  `id_historia_clinica` int(11) NOT NULL,
  `id_tratamiento` int(11) NOT NULL,
  `id_medicamento` int(11) DEFAULT NULL,
  `fecha_hora` datetime NOT NULL,
  `dosis` varchar(50) DEFAULT NULL,
  `observaciones` text DEFAULT NULL,
  `id_veterinario` int(11) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Volcado de datos para la tabla `tratamientos_aplicados`
--

INSERT INTO `tratamientos_aplicados` (`id_tratamiento_aplicado`, `id_historia_clinica`, `id_tratamiento`, `id_medicamento`, `fecha_hora`, `dosis`, `observaciones`, `id_veterinario`) VALUES
(1, 2, 1, NULL, '2023-04-10 10:35:00', NULL, 'Vacuna antirrábica administrada sin reacciones adversas', 1),
(2, 3, 6, 2, '2023-04-10 11:40:00', '250mg/12h por 5 días', 'Tratamiento para gastroenteritis', 2),
(3, 5, 5, NULL, '2023-04-10 15:40:00', NULL, 'Limpieza dental completa bajo anestesia', 4),
(4, 6, 8, 4, '2023-04-10 16:40:00', '10mg/24h por 3 días', 'Tratamiento para dermatitis alérgica', 5),
(5, 6, 9, NULL, '2025-05-14 19:51:47', NULL, 'Tratamiento de prueba', 1);

--
-- Disparadores `tratamientos_aplicados`
--
DELIMITER $$
CREATE TRIGGER `validar_tratamiento_compatible` BEFORE INSERT ON `tratamientos_aplicados` FOR EACH ROW BEGIN
    -- Variables para almacenar los datos de la mascota
    DECLARE v_id_especie INT;
    DECLARE v_id_raza INT;
    DECLARE v_es_compatible BOOLEAN DEFAULT FALSE;
    DECLARE v_nombre_especie VARCHAR(50);
    DECLARE v_nombre_raza VARCHAR(50);

    -- Obtener especie y raza de la mascota a través de la historia clínica
    SELECT m.id_especie, m.id_raza, e.nombre, r.nombre
    INTO v_id_especie, v_id_raza, v_nombre_especie, v_nombre_raza
    FROM historias_clinicas hc
    INNER JOIN mascotas m ON hc.id_mascota = m.id_mascota
    INNER JOIN especies e ON m.id_especie = e.id_especie
    INNER JOIN razas r ON m.id_raza = r.id_raza
    WHERE hc.id_historia_clinica = NEW.id_historia_clinica;

    -- Verificar si el tratamiento es compatible con la especie/raza
    SELECT COUNT(*) > 0 INTO v_es_compatible
    FROM tratamientos_compatibles tc
    WHERE tc.id_tratamiento = NEW.id_tratamiento
    AND tc.id_especie = v_id_especie
    AND (tc.id_raza = v_id_raza OR tc.id_raza IS NULL);

    -- Si no es compatible, registrar error y rechazar la operación
    IF NOT v_es_compatible THEN
        -- Registrar el intento fallido
        INSERT INTO registro_errores_clinicos (
            tipo_error,
            descripcion,
            id_mascota,
            id_tratamiento,
            id_veterinario,
            fecha_hora,
            usuario
        )
        SELECT
            'Tratamiento incompatible',
            CONCAT('Intento de aplicar tratamiento no compatible. Especie: ',
                   v_nombre_especie, ', Raza: ', v_nombre_raza),
            hc.id_mascota,
            NEW.id_tratamiento,
            NEW.id_veterinario,
            NOW(),
            USER()
        FROM historias_clinicas hc
        WHERE hc.id_historia_clinica = NEW.id_historia_clinica;

        -- Rechazar la operación
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Error: Tratamiento incompatible con la especie/raza de la mascota';
    END IF;
END
$$
DELIMITER ;

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `tratamientos_compatibles`
--

CREATE TABLE `tratamientos_compatibles` (
  `id_tratamiento_compatible` int(11) NOT NULL,
  `id_tratamiento` int(11) NOT NULL,
  `id_especie` int(11) NOT NULL,
  `id_raza` int(11) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Volcado de datos para la tabla `tratamientos_compatibles`
--

INSERT INTO `tratamientos_compatibles` (`id_tratamiento_compatible`, `id_tratamiento`, `id_especie`, `id_raza`) VALUES
(1, 1, 1, NULL),
(2, 1, 2, NULL),
(3, 2, 1, NULL),
(4, 2, 2, NULL),
(5, 3, 1, NULL),
(6, 3, 2, NULL),
(7, 3, 3, NULL),
(8, 3, 4, NULL),
(9, 3, 5, NULL),
(10, 4, 1, NULL),
(11, 4, 2, NULL),
(12, 5, 1, NULL),
(13, 5, 2, NULL),
(14, 6, 1, NULL),
(15, 6, 2, NULL),
(16, 6, 3, NULL),
(17, 6, 4, NULL),
(18, 6, 5, NULL),
(19, 7, 1, NULL),
(20, 7, 2, NULL),
(21, 8, 1, NULL),
(22, 8, 2, NULL),
(23, 9, 1, NULL),
(24, 9, 2, NULL),
(25, 10, 1, NULL),
(26, 10, 2, NULL);

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `veterinarios`
--

CREATE TABLE `veterinarios` (
  `id_veterinario` int(11) NOT NULL,
  `id_cargo` int(11) NOT NULL,
  `numero_licencia` varchar(50) NOT NULL,
  `nombre` varchar(100) NOT NULL,
  `apellido` varchar(100) NOT NULL,
  `especialidad` varchar(100) DEFAULT NULL,
  `telefono` varchar(20) DEFAULT NULL,
  `email` varchar(100) DEFAULT NULL,
  `activo` tinyint(1) DEFAULT 1,
  `fecha_contratacion` date NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Volcado de datos para la tabla `veterinarios`
--

INSERT INTO `veterinarios` (`id_veterinario`, `id_cargo`, `numero_licencia`, `nombre`, `apellido`, `especialidad`, `telefono`, `email`, `activo`, `fecha_contratacion`) VALUES
(1, 1, 'VET-12345', 'Alejandro', 'Ramírez', 'Medicina General', '3101234567', 'alejandro.ramirez@clinicaaltavida.com', 1, '2018-02-15'),
(2, 2, 'VET-23456', 'Valentina', 'Gutiérrez', 'Medicina Interna', '3122345678', 'valentina.gutierrez@clinicaaltavida.com', 1, '2018-03-20'),
(3, 3, 'VET-34567', 'Ricardo', 'Mendoza', 'Administración Médica', '3203456789', 'ricardo.mendoza@clinicaaltavida.com', 1, '2018-01-10'),
(4, 4, 'VET-45678', 'Carolina', 'Vargas', 'Cirugía', '3504567890', 'carolina.vargas@clinicaaltavida.com', 1, '2019-04-05'),
(5, 5, 'VET-56789', 'Javier', 'Ortiz', 'Dermatología', '3155678901', 'javier.ortiz@clinicaaltavida.com', 1, '2019-05-15');

--
-- Índices para tablas volcadas
--

--
-- Indices de la tabla `altas_medicas`
--
ALTER TABLE `altas_medicas`
  ADD PRIMARY KEY (`id_alta`),
  ADD KEY `id_historia_clinica` (`id_historia_clinica`),
  ADD KEY `id_veterinario` (`id_veterinario`);

--
-- Indices de la tabla `cargos`
--
ALTER TABLE `cargos`
  ADD PRIMARY KEY (`id_cargo`);

--
-- Indices de la tabla `citas`
--
ALTER TABLE `citas`
  ADD PRIMARY KEY (`id_cita`),
  ADD KEY `id_mascota` (`id_mascota`),
  ADD KEY `id_veterinario` (`id_veterinario`);

--
-- Indices de la tabla `detalle_facturas`
--
ALTER TABLE `detalle_facturas`
  ADD PRIMARY KEY (`id_detalle`),
  ADD KEY `id_factura` (`id_factura`),
  ADD KEY `id_cita` (`id_cita`),
  ADD KEY `id_tratamiento` (`id_tratamiento`);

--
-- Indices de la tabla `diagnosticos`
--
ALTER TABLE `diagnosticos`
  ADD PRIMARY KEY (`id_diagnostico`);

--
-- Indices de la tabla `especies`
--
ALTER TABLE `especies`
  ADD PRIMARY KEY (`id_especie`);

--
-- Indices de la tabla `eventos_criticos`
--
ALTER TABLE `eventos_criticos`
  ADD PRIMARY KEY (`id_evento`),
  ADD KEY `id_mascota` (`id_mascota`),
  ADD KEY `id_historia_clinica` (`id_historia_clinica`),
  ADD KEY `id_diagnostico` (`id_diagnostico`),
  ADD KEY `notificado_a` (`notificado_a`);

--
-- Indices de la tabla `facturas`
--
ALTER TABLE `facturas`
  ADD PRIMARY KEY (`id_factura`),
  ADD KEY `id_propietario` (`id_propietario`);

--
-- Indices de la tabla `historias_clinicas`
--
ALTER TABLE `historias_clinicas`
  ADD PRIMARY KEY (`id_historia_clinica`),
  ADD KEY `id_cita` (`id_cita`),
  ADD KEY `id_mascota` (`id_mascota`),
  ADD KEY `id_veterinario` (`id_veterinario`),
  ADD KEY `id_diagnostico` (`id_diagnostico`);

--
-- Indices de la tabla `inventario_medicamentos`
--
ALTER TABLE `inventario_medicamentos`
  ADD PRIMARY KEY (`id_inventario`),
  ADD KEY `id_medicamento` (`id_medicamento`);

--
-- Indices de la tabla `mascotas`
--
ALTER TABLE `mascotas`
  ADD PRIMARY KEY (`id_mascota`),
  ADD KEY `id_propietario` (`id_propietario`),
  ADD KEY `id_especie` (`id_especie`),
  ADD KEY `id_raza` (`id_raza`);

--
-- Indices de la tabla `medicamentos`
--
ALTER TABLE `medicamentos`
  ADD PRIMARY KEY (`id_medicamento`);

--
-- Indices de la tabla `notificaciones_administrativas`
--
ALTER TABLE `notificaciones_administrativas`
  ADD PRIMARY KEY (`id_notificacion`);

--
-- Indices de la tabla `propietarios`
--
ALTER TABLE `propietarios`
  ADD PRIMARY KEY (`id_propietario`);

--
-- Indices de la tabla `razas`
--
ALTER TABLE `razas`
  ADD PRIMARY KEY (`id_raza`),
  ADD KEY `id_especie` (`id_especie`);

--
-- Indices de la tabla `registro_errores_clinicos`
--
ALTER TABLE `registro_errores_clinicos`
  ADD PRIMARY KEY (`id_error`),
  ADD KEY `id_mascota` (`id_mascota`),
  ADD KEY `id_tratamiento` (`id_tratamiento`),
  ADD KEY `id_veterinario` (`id_veterinario`);

--
-- Indices de la tabla `solicitudes_reabastecimiento`
--
ALTER TABLE `solicitudes_reabastecimiento`
  ADD PRIMARY KEY (`id_solicitud`),
  ADD KEY `id_medicamento` (`id_medicamento`),
  ADD KEY `id_jefe_clinico` (`id_jefe_clinico`);

--
-- Indices de la tabla `tratamientos`
--
ALTER TABLE `tratamientos`
  ADD PRIMARY KEY (`id_tratamiento`);

--
-- Indices de la tabla `tratamientos_aplicados`
--
ALTER TABLE `tratamientos_aplicados`
  ADD PRIMARY KEY (`id_tratamiento_aplicado`),
  ADD KEY `id_historia_clinica` (`id_historia_clinica`),
  ADD KEY `id_tratamiento` (`id_tratamiento`),
  ADD KEY `id_medicamento` (`id_medicamento`),
  ADD KEY `id_veterinario` (`id_veterinario`);

--
-- Indices de la tabla `tratamientos_compatibles`
--
ALTER TABLE `tratamientos_compatibles`
  ADD PRIMARY KEY (`id_tratamiento_compatible`),
  ADD KEY `id_tratamiento` (`id_tratamiento`),
  ADD KEY `id_especie` (`id_especie`),
  ADD KEY `id_raza` (`id_raza`);

--
-- Indices de la tabla `veterinarios`
--
ALTER TABLE `veterinarios`
  ADD PRIMARY KEY (`id_veterinario`),
  ADD UNIQUE KEY `numero_licencia` (`numero_licencia`),
  ADD KEY `id_cargo` (`id_cargo`);

--
-- AUTO_INCREMENT de las tablas volcadas
--

--
-- AUTO_INCREMENT de la tabla `altas_medicas`
--
ALTER TABLE `altas_medicas`
  MODIFY `id_alta` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=7;

--
-- AUTO_INCREMENT de la tabla `cargos`
--
ALTER TABLE `cargos`
  MODIFY `id_cargo` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=6;

--
-- AUTO_INCREMENT de la tabla `citas`
--
ALTER TABLE `citas`
  MODIFY `id_cita` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=11;

--
-- AUTO_INCREMENT de la tabla `detalle_facturas`
--
ALTER TABLE `detalle_facturas`
  MODIFY `id_detalle` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=8;

--
-- AUTO_INCREMENT de la tabla `diagnosticos`
--
ALTER TABLE `diagnosticos`
  MODIFY `id_diagnostico` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=11;

--
-- AUTO_INCREMENT de la tabla `especies`
--
ALTER TABLE `especies`
  MODIFY `id_especie` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=6;

--
-- AUTO_INCREMENT de la tabla `eventos_criticos`
--
ALTER TABLE `eventos_criticos`
  MODIFY `id_evento` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=2;

--
-- AUTO_INCREMENT de la tabla `facturas`
--
ALTER TABLE `facturas`
  MODIFY `id_factura` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=7;

--
-- AUTO_INCREMENT de la tabla `historias_clinicas`
--
ALTER TABLE `historias_clinicas`
  MODIFY `id_historia_clinica` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=7;

--
-- AUTO_INCREMENT de la tabla `inventario_medicamentos`
--
ALTER TABLE `inventario_medicamentos`
  MODIFY `id_inventario` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=11;

--
-- AUTO_INCREMENT de la tabla `mascotas`
--
ALTER TABLE `mascotas`
  MODIFY `id_mascota` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=11;

--
-- AUTO_INCREMENT de la tabla `medicamentos`
--
ALTER TABLE `medicamentos`
  MODIFY `id_medicamento` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=11;

--
-- AUTO_INCREMENT de la tabla `notificaciones_administrativas`
--
ALTER TABLE `notificaciones_administrativas`
  MODIFY `id_notificacion` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=7;

--
-- AUTO_INCREMENT de la tabla `propietarios`
--
ALTER TABLE `propietarios`
  MODIFY `id_propietario` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=11;

--
-- AUTO_INCREMENT de la tabla `razas`
--
ALTER TABLE `razas`
  MODIFY `id_raza` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=21;

--
-- AUTO_INCREMENT de la tabla `registro_errores_clinicos`
--
ALTER TABLE `registro_errores_clinicos`
  MODIFY `id_error` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=4;

--
-- AUTO_INCREMENT de la tabla `solicitudes_reabastecimiento`
--
ALTER TABLE `solicitudes_reabastecimiento`
  MODIFY `id_solicitud` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=7;

--
-- AUTO_INCREMENT de la tabla `tratamientos`
--
ALTER TABLE `tratamientos`
  MODIFY `id_tratamiento` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=11;

--
-- AUTO_INCREMENT de la tabla `tratamientos_aplicados`
--
ALTER TABLE `tratamientos_aplicados`
  MODIFY `id_tratamiento_aplicado` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=6;

--
-- AUTO_INCREMENT de la tabla `tratamientos_compatibles`
--
ALTER TABLE `tratamientos_compatibles`
  MODIFY `id_tratamiento_compatible` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=27;

--
-- AUTO_INCREMENT de la tabla `veterinarios`
--
ALTER TABLE `veterinarios`
  MODIFY `id_veterinario` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=6;

--
-- Restricciones para tablas volcadas
--

--
-- Filtros para la tabla `altas_medicas`
--
ALTER TABLE `altas_medicas`
  ADD CONSTRAINT `altas_medicas_ibfk_1` FOREIGN KEY (`id_historia_clinica`) REFERENCES `historias_clinicas` (`id_historia_clinica`),
  ADD CONSTRAINT `altas_medicas_ibfk_2` FOREIGN KEY (`id_veterinario`) REFERENCES `veterinarios` (`id_veterinario`);

--
-- Filtros para la tabla `citas`
--
ALTER TABLE `citas`
  ADD CONSTRAINT `citas_ibfk_1` FOREIGN KEY (`id_mascota`) REFERENCES `mascotas` (`id_mascota`),
  ADD CONSTRAINT `citas_ibfk_2` FOREIGN KEY (`id_veterinario`) REFERENCES `veterinarios` (`id_veterinario`);

--
-- Filtros para la tabla `detalle_facturas`
--
ALTER TABLE `detalle_facturas`
  ADD CONSTRAINT `detalle_facturas_ibfk_1` FOREIGN KEY (`id_factura`) REFERENCES `facturas` (`id_factura`),
  ADD CONSTRAINT `detalle_facturas_ibfk_2` FOREIGN KEY (`id_cita`) REFERENCES `citas` (`id_cita`),
  ADD CONSTRAINT `detalle_facturas_ibfk_3` FOREIGN KEY (`id_tratamiento`) REFERENCES `tratamientos` (`id_tratamiento`);

--
-- Filtros para la tabla `eventos_criticos`
--
ALTER TABLE `eventos_criticos`
  ADD CONSTRAINT `eventos_criticos_ibfk_1` FOREIGN KEY (`id_mascota`) REFERENCES `mascotas` (`id_mascota`),
  ADD CONSTRAINT `eventos_criticos_ibfk_2` FOREIGN KEY (`id_historia_clinica`) REFERENCES `historias_clinicas` (`id_historia_clinica`),
  ADD CONSTRAINT `eventos_criticos_ibfk_3` FOREIGN KEY (`id_diagnostico`) REFERENCES `diagnosticos` (`id_diagnostico`),
  ADD CONSTRAINT `eventos_criticos_ibfk_4` FOREIGN KEY (`notificado_a`) REFERENCES `veterinarios` (`id_veterinario`);

--
-- Filtros para la tabla `facturas`
--
ALTER TABLE `facturas`
  ADD CONSTRAINT `facturas_ibfk_1` FOREIGN KEY (`id_propietario`) REFERENCES `propietarios` (`id_propietario`);

--
-- Filtros para la tabla `historias_clinicas`
--
ALTER TABLE `historias_clinicas`
  ADD CONSTRAINT `historias_clinicas_ibfk_1` FOREIGN KEY (`id_cita`) REFERENCES `citas` (`id_cita`),
  ADD CONSTRAINT `historias_clinicas_ibfk_2` FOREIGN KEY (`id_mascota`) REFERENCES `mascotas` (`id_mascota`),
  ADD CONSTRAINT `historias_clinicas_ibfk_3` FOREIGN KEY (`id_veterinario`) REFERENCES `veterinarios` (`id_veterinario`),
  ADD CONSTRAINT `historias_clinicas_ibfk_4` FOREIGN KEY (`id_diagnostico`) REFERENCES `diagnosticos` (`id_diagnostico`);

--
-- Filtros para la tabla `inventario_medicamentos`
--
ALTER TABLE `inventario_medicamentos`
  ADD CONSTRAINT `inventario_medicamentos_ibfk_1` FOREIGN KEY (`id_medicamento`) REFERENCES `medicamentos` (`id_medicamento`);

--
-- Filtros para la tabla `mascotas`
--
ALTER TABLE `mascotas`
  ADD CONSTRAINT `mascotas_ibfk_1` FOREIGN KEY (`id_propietario`) REFERENCES `propietarios` (`id_propietario`),
  ADD CONSTRAINT `mascotas_ibfk_2` FOREIGN KEY (`id_especie`) REFERENCES `especies` (`id_especie`),
  ADD CONSTRAINT `mascotas_ibfk_3` FOREIGN KEY (`id_raza`) REFERENCES `razas` (`id_raza`);

--
-- Filtros para la tabla `razas`
--
ALTER TABLE `razas`
  ADD CONSTRAINT `razas_ibfk_1` FOREIGN KEY (`id_especie`) REFERENCES `especies` (`id_especie`);

--
-- Filtros para la tabla `registro_errores_clinicos`
--
ALTER TABLE `registro_errores_clinicos`
  ADD CONSTRAINT `registro_errores_clinicos_ibfk_1` FOREIGN KEY (`id_mascota`) REFERENCES `mascotas` (`id_mascota`),
  ADD CONSTRAINT `registro_errores_clinicos_ibfk_2` FOREIGN KEY (`id_tratamiento`) REFERENCES `tratamientos` (`id_tratamiento`),
  ADD CONSTRAINT `registro_errores_clinicos_ibfk_3` FOREIGN KEY (`id_veterinario`) REFERENCES `veterinarios` (`id_veterinario`);

--
-- Filtros para la tabla `solicitudes_reabastecimiento`
--
ALTER TABLE `solicitudes_reabastecimiento`
  ADD CONSTRAINT `solicitudes_reabastecimiento_ibfk_1` FOREIGN KEY (`id_medicamento`) REFERENCES `medicamentos` (`id_medicamento`),
  ADD CONSTRAINT `solicitudes_reabastecimiento_ibfk_2` FOREIGN KEY (`id_jefe_clinico`) REFERENCES `veterinarios` (`id_veterinario`);

--
-- Filtros para la tabla `tratamientos_aplicados`
--
ALTER TABLE `tratamientos_aplicados`
  ADD CONSTRAINT `tratamientos_aplicados_ibfk_1` FOREIGN KEY (`id_historia_clinica`) REFERENCES `historias_clinicas` (`id_historia_clinica`),
  ADD CONSTRAINT `tratamientos_aplicados_ibfk_2` FOREIGN KEY (`id_tratamiento`) REFERENCES `tratamientos` (`id_tratamiento`),
  ADD CONSTRAINT `tratamientos_aplicados_ibfk_3` FOREIGN KEY (`id_medicamento`) REFERENCES `medicamentos` (`id_medicamento`),
  ADD CONSTRAINT `tratamientos_aplicados_ibfk_4` FOREIGN KEY (`id_veterinario`) REFERENCES `veterinarios` (`id_veterinario`);

--
-- Filtros para la tabla `tratamientos_compatibles`
--
ALTER TABLE `tratamientos_compatibles`
  ADD CONSTRAINT `tratamientos_compatibles_ibfk_1` FOREIGN KEY (`id_tratamiento`) REFERENCES `tratamientos` (`id_tratamiento`),
  ADD CONSTRAINT `tratamientos_compatibles_ibfk_2` FOREIGN KEY (`id_especie`) REFERENCES `especies` (`id_especie`),
  ADD CONSTRAINT `tratamientos_compatibles_ibfk_3` FOREIGN KEY (`id_raza`) REFERENCES `razas` (`id_raza`);

--
-- Filtros para la tabla `veterinarios`
--
ALTER TABLE `veterinarios`
  ADD CONSTRAINT `veterinarios_ibfk_1` FOREIGN KEY (`id_cargo`) REFERENCES `cargos` (`id_cargo`);
COMMIT;

/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
