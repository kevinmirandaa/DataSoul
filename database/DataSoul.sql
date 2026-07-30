-- =============================================================================
-- DataSoul CR — Base de Datos
-- Sistema de gestión para Soul CR, joyería artesanal de Pital, San Carlos.
-- Cubre inventario, ventas, clientes y finanzas.
-- SQL Server 2019+ requerido (usa CREATE OR ALTER, funciones de ventana, XML).
-- =============================================================================

-- sección 0: limpieza previa
-- Cierra conexiones activas y elimina la DB si ya existe, para un deploy limpio.


 USE master;
GO

IF EXISTS (SELECT name FROM sys.databases WHERE name = 'DataSoul')
    ALTER DATABASE DataSoul SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
GO

IF EXISTS (SELECT name FROM sys.databases WHERE name = 'DataSoul')
    DROP DATABASE DataSoul;
GO

-- sección 1: creación de la base de datos

IF NOT EXISTS (SELECT name FROM sys.databases WHERE name = 'DataSoul')
    CREATE DATABASE DataSoul;
GO

USE DataSoul;
GO


-- sección 2: tipos de datos personalizados
-- Alias tipados que centralizan el dominio de cada campo de negocio.
-- Cambiar el tipo base aquí actualiza todas las tablas que lo usan.

CREATE TYPE tipo_email           FROM VARCHAR(30);
GO
CREATE TYPE tipo_telefono        FROM VARCHAR(20);
GO
CREATE TYPE tipo_monto           FROM DECIMAL(10,2);
GO
CREATE TYPE tipo_nombre_persona  FROM VARCHAR(100);
GO
CREATE TYPE tipo_codigo_producto FROM VARCHAR(50);
GO

-- sección 3: creación de tablas

-- grupo a: catálogo FN4
-- Tablas de enumeración que evitan repetir strings como 'activo'/'inactivo'
-- en las tablas principales. El CHECK garantiza que solo entren valores válidos.

-- estado posible de un cliente
CREATE TABLE estado_cliente (
    id_estado   TINYINT         NOT NULL,
    descripcion VARCHAR(20) NOT NULL,
    CONSTRAINT PK_estado_cliente PRIMARY KEY (id_estado),
    CONSTRAINT CHK_estado_cliente_descripcion CHECK (descripcion IN ('activo','inactivo','suspendido'))
);
GO

-- estado posible de un pago o ingreso
CREATE TABLE estado_pago (
    id_estado   TINYINT         NOT NULL,
    descripcion VARCHAR(20) NOT NULL,
    CONSTRAINT PK_estado_pago PRIMARY KEY (id_estado),
    CONSTRAINT CHK_estado_pago_descripcion CHECK (descripcion IN ('aplicado','pendiente','rechazado','devuelto'))
);
GO

-- estado posible de una cuenta bancaria
CREATE TABLE estado_cuenta (
    id_estado   INT         NOT NULL,
    descripcion VARCHAR(20) NOT NULL,
    CONSTRAINT PK_estado_cuenta PRIMARY KEY (id_estado),
    CONSTRAINT CHK_estado_cuenta_descripcion CHECK (descripcion IN ('activa','inactiva','bloqueada'))
);
GO

-- estado posible de un ítem en inventario
CREATE TABLE estado_inventario (
    id_estado   INT         NOT NULL,
    descripcion VARCHAR(20) NOT NULL,
    CONSTRAINT PK_estado_inventario PRIMARY KEY (id_estado),
    CONSTRAINT CHK_estado_inventario_descripcion CHECK (descripcion IN ('activo','descontinuado','revision'))
);
GO

-- indica si una categoría de producto está activa
CREATE TABLE activa_inventario (
    id_estado   INT         NOT NULL,
    descripcion VARCHAR(20) NOT NULL,
    CONSTRAINT PK_activa_inventario PRIMARY KEY (id_estado),
    CONSTRAINT CHK_activa_inventario_descripcion CHECK (descripcion IN ('Si','No'))
);
GO

-- disponibilidad de un producto para la venta
CREATE TABLE disponible_inventario (
    id_estado   INT         NOT NULL,
    descripcion VARCHAR(20) NOT NULL,
    CONSTRAINT PK_disponible_inventario PRIMARY KEY (id_estado),
    CONSTRAINT CHK_disponible_inventario_descripcion CHECK (descripcion IN ('disponible','agotado','bajo_pedido'))
);
GO

-- disponibilidad de un material para producción
CREATE TABLE disponibilidad_material (
    id_estado   INT         NOT NULL,
    descripcion VARCHAR(20) NOT NULL,
    CONSTRAINT PK_disponibilidad_material PRIMARY KEY (id_estado),
    CONSTRAINT CHK_disponibilidad_material_descripcion CHECK (descripcion IN ('disponible','no_disponible'))
);
GO

-- grupo b: tablas geográficas
-- Jerarquía territorial: provincia → cantón → distrito.
-- Solo se usa ON UPDATE CASCADE; los distritos no se borran en cascada
-- para proteger direcciones de clientes que ya están registradas.

-- provincias de costa rica
CREATE TABLE provincias (
    id_provincia TINYINT     NOT NULL,
    provincia    VARCHAR(15) NOT NULL,
    CONSTRAINT PK_provincias PRIMARY KEY (id_provincia)
);
GO

-- cantones agrupados por provincia
CREATE TABLE cantones (
    id_canton SMALLINT    NOT NULL,
    canton    VARCHAR(15) NOT NULL,
    provincia TINYINT     NOT NULL,
    CONSTRAINT PK_cantones PRIMARY KEY (id_canton),
    CONSTRAINT FK_cantones_provincia FOREIGN KEY (provincia)
        REFERENCES provincias(id_provincia)
        ON UPDATE CASCADE
        ON DELETE NO ACTION
);
GO

-- distritos agrupados por cantón
CREATE TABLE distritos (
    id_distrito INT         NOT NULL,
    distrito    VARCHAR(20) NOT NULL,
    canton      SMALLINT    NOT NULL,
    CONSTRAINT PK_distritos PRIMARY KEY (id_distrito),
    CONSTRAINT FK_distritos_canton FOREIGN KEY (canton)
        REFERENCES cantones(id_canton)
        ON UPDATE CASCADE
        ON DELETE NO ACTION
);
GO

-- grupo c: clientes
-- Atributos multivaluados (email, teléfono, dirección) en tablas separadas.
-- ON DELETE CASCADE desde cliente los elimina automáticamente si se borra el cliente.

-- datos principales del cliente de soul cr
CREATE TABLE cliente (
    id_cliente     INT                 NOT NULL IDENTITY(1,1),
    nombre         tipo_nombre_persona NOT NULL,
    apellido1      tipo_nombre_persona NOT NULL,
    apellido2      VARCHAR(20)         NULL,
    estado_cliente TINYINT             NOT NULL CONSTRAINT DF_cliente_estado DEFAULT 1,
    fecha_registro DATE                NOT NULL CONSTRAINT DF_cliente_fecha  DEFAULT GETDATE(),
    CONSTRAINT PK_cliente PRIMARY KEY (id_cliente),
    CONSTRAINT FK_cliente_estado FOREIGN KEY (estado_cliente)
        REFERENCES estado_cliente(id_estado),
    CONSTRAINT CHK_cliente_nombre    CHECK (LEN(nombre)    >= 2),
    CONSTRAINT CHK_cliente_apellido1 CHECK (LEN(apellido1) >= 2)
);
GO

-- correos electrónicos de clientes (multivaluado)
CREATE TABLE email (
    id_email   INT        NOT NULL IDENTITY(1,1),
    id_cliente INT        NOT NULL,
    email      tipo_email NOT NULL,
    CONSTRAINT PK_email PRIMARY KEY (id_email),
    CONSTRAINT FK_email_cliente FOREIGN KEY (id_cliente)
        REFERENCES cliente(id_cliente)
        ON DELETE CASCADE
        ON UPDATE CASCADE,
    CONSTRAINT UQ_email_email UNIQUE (email),
    -- verifica: arroba presente con al menos un char antes, punto después del arroba,
    -- y que no haya doble arroba.
    CONSTRAINT CHK_email_formato CHECK (
        CHARINDEX('@', email) > 1
        AND CHARINDEX('.', email, CHARINDEX('@', email)) > CHARINDEX('@', email)
        AND email NOT LIKE '%@%@%'
    )
);
GO

-- un teléfono por cliente, pk en id_cliente
CREATE TABLE telefonos (
    id_cliente INT           NOT NULL,
    telefono   tipo_telefono NOT NULL,
    CONSTRAINT PK_telefonos PRIMARY KEY (id_cliente),
    CONSTRAINT FK_telefonos_cliente FOREIGN KEY (id_cliente)
        REFERENCES cliente(id_cliente)
        ON DELETE CASCADE
        ON UPDATE CASCADE,
    CONSTRAINT CHK_telefonos_formato CHECK (
        telefono NOT LIKE '%[^0-9 + -]%'
    )
);
GO

-- direcciones de clientes, pk compuesta (id_cliente, id_distrito)
CREATE TABLE direccion (
    id_cliente  INT NOT NULL,
    id_distrito INT NOT NULL,
    CONSTRAINT PK_direccion PRIMARY KEY (id_cliente, id_distrito),
    CONSTRAINT FK_direccion_cliente FOREIGN KEY (id_cliente)
        REFERENCES cliente(id_cliente)
        ON DELETE CASCADE
        ON UPDATE CASCADE,
    CONSTRAINT FK_direccion_distrito FOREIGN KEY (id_distrito)
        REFERENCES distritos(id_distrito)
        ON UPDATE CASCADE
);
GO

-- grupo d: productos, categorías e inventario
-- producto se conecta a categoría y material por FK; inventario tiene
-- relación 1:1 con producto (UQ sobre id_producto).

-- categorías de joyas de soul cr
CREATE TABLE categoria_producto (
    id_categoria   INT          NOT NULL IDENTITY(1,1),
    nombre         VARCHAR(100) NOT NULL,
    descripcion    VARCHAR(255) NULL,
    activa         INT          NOT NULL DEFAULT 1,
    comision_venta DECIMAL(5,2) NULL,
    CONSTRAINT PK_categoria_producto PRIMARY KEY (id_categoria),
    CONSTRAINT FK_categoria_activa FOREIGN KEY (activa)
        REFERENCES activa_inventario(id_estado),
    CONSTRAINT CHK_categoria_comision CHECK (comision_venta BETWEEN 0 AND 100)
);
GO

-- materiales de fabricación (costo_unitario: campo simple, sin fk)
CREATE TABLE tipo_material (
    id_material                INT           NOT NULL IDENTITY(1,1),
    nombre_material            VARCHAR(100)  NOT NULL,
    proveedor                  VARCHAR(100)  NULL,
    costo_unitario             TINYINT       NULL,
    densidad                   DECIMAL(10,2) NULL,
    fecha_ultima_actualizacion DATE          NULL,
    descripcion                VARCHAR(255)  NULL,
    disponibilidad             INT           NOT NULL DEFAULT 1,
    CONSTRAINT PK_tipo_material PRIMARY KEY (id_material),
    CONSTRAINT FK_material_disponibilidad FOREIGN KEY (disponibilidad)
        REFERENCES disponibilidad_material(id_estado)
);
GO

-- catálogo de joyas disponibles en soul cr
CREATE TABLE producto (
    id_producto    INT                  NOT NULL IDENTITY(1,1),
    id_categoria   INT                  NOT NULL,
    nombre         VARCHAR(100)         NOT NULL,
    descripcion    VARCHAR(100)         NULL,
    precio_venta   DECIMAL(10,2)        NOT NULL,
    codigo         tipo_codigo_producto NOT NULL,
    fecha_creacion DATE                 NOT NULL DEFAULT GETDATE(),
    disponibilidad INT                  NOT NULL DEFAULT 1,
    material       INT                  NOT NULL,
    tipo           VARCHAR(50)          NULL,
    imagen_url     VARCHAR(255)         NULL,
    CONSTRAINT PK_producto PRIMARY KEY (id_producto),
    CONSTRAINT FK_producto_categoria FOREIGN KEY (id_categoria)
        REFERENCES categoria_producto(id_categoria)
        ON UPDATE CASCADE
        ON DELETE NO ACTION,
    CONSTRAINT FK_producto_disponibilidad FOREIGN KEY (disponibilidad)
        REFERENCES disponible_inventario(id_estado),
    CONSTRAINT FK_producto_material FOREIGN KEY (material)
        REFERENCES tipo_material(id_material)
        ON UPDATE CASCADE
        ON DELETE NO ACTION,
    CONSTRAINT UQ_producto_codigo UNIQUE (codigo),
    CONSTRAINT CHK_producto_precio CHECK (precio_venta > 0),
    CONSTRAINT CHK_producto_codigo CHECK (LEN(codigo) >= 3 AND codigo NOT LIKE '% %')
);
GO

-- control de existencias, relación 1:1 con producto
CREATE TABLE inventario (
    id_inventario       INT NOT NULL IDENTITY(1,1),
    id_producto         INT NOT NULL,
    unidades_vendidas   INT NOT NULL CONSTRAINT DF_inventario_unidades DEFAULT 0,
    cantidad_disponible INT NOT NULL,
    cantidad_minima     INT NOT NULL,
    cantidad_maxima     INT NOT NULL,
    estado              INT NOT NULL DEFAULT 1,
    CONSTRAINT PK_inventario PRIMARY KEY (id_inventario),
    CONSTRAINT UQ_inventario_producto UNIQUE (id_producto),
    CONSTRAINT FK_inventario_producto FOREIGN KEY (id_producto)
        REFERENCES producto(id_producto)
        ON UPDATE CASCADE
        ON DELETE NO ACTION,
    CONSTRAINT FK_inventario_estado FOREIGN KEY (estado)
        REFERENCES estado_inventario(id_estado),
    CONSTRAINT CHK_inventario_disponible CHECK (cantidad_disponible >= 0),
    CONSTRAINT CHK_inventario_minima     CHECK (cantidad_minima >= 0),
    CONSTRAINT CHK_inventario_maxima     CHECK (cantidad_maxima >= cantidad_minima)
);
GO

-- grupo e: ventas y pagos
-- compra es el encabezado; detalle_compra guarda las líneas (PK compuesta).
-- pago e ingreso registran el flujo de dinero de forma independiente,
-- lo que permite confirmar cobros sin tocar directamente la compra.

-- encabezado de cada venta realizada
CREATE TABLE compra (
    id_compra      INT           NOT NULL IDENTITY(1,1),
    id_cliente     INT           NOT NULL,
    numero_factura VARCHAR(50)   NULL,
    fecha_compra   DATE          NOT NULL CONSTRAINT DF_compra_fecha  DEFAULT GETDATE(),
    monto_total    tipo_monto    NOT NULL DEFAULT 0,
    estado_pago    TINYINT       NOT NULL CONSTRAINT DF_compra_estado DEFAULT 2,
    flujo_ingresos DECIMAL(10,2) NULL,
    comentarios    VARCHAR(255)  NULL,
    CONSTRAINT PK_compra PRIMARY KEY (id_compra),
    CONSTRAINT FK_compra_cliente FOREIGN KEY (id_cliente)
        REFERENCES cliente(id_cliente)
        ON UPDATE CASCADE
        ON DELETE NO ACTION,
    CONSTRAINT FK_compra_estado FOREIGN KEY (estado_pago)
        REFERENCES estado_pago(id_estado),
    CONSTRAINT UQ_compra_factura UNIQUE (numero_factura)
);
GO

-- entidad débil, pk compuesta (id_compra, id_producto)
CREATE TABLE detalle_compra (
    id_compra       INT           NOT NULL,
    id_producto     INT           NOT NULL,
    cantidad        INT           NOT NULL,
    precio_unitario DECIMAL(10,2) NOT NULL,
    CONSTRAINT PK_detalle_compra PRIMARY KEY (id_compra, id_producto),
    CONSTRAINT FK_detalle_compra_compra FOREIGN KEY (id_compra)
        REFERENCES compra(id_compra)
        ON DELETE NO ACTION
        ON UPDATE CASCADE,
    CONSTRAINT FK_detalle_compra_producto FOREIGN KEY (id_producto)
        REFERENCES producto(id_producto)
        ON UPDATE CASCADE,
    CONSTRAINT CHK_detalle_cantidad        CHECK (cantidad        > 0),
    CONSTRAINT CHK_detalle_precio_unitario CHECK (precio_unitario > 0)
);
GO

-- pagos registrados por compra
CREATE TABLE pago (
    id_pago            INT           NOT NULL IDENTITY(1,1),
    id_cliente         INT           NOT NULL,
    id_compra          INT           NOT NULL,
    numero_referencia  VARCHAR(50)   NULL,
    estado_pago        TINYINT       NOT NULL,
    numero_comprobante VARCHAR(100)  NULL,
    monto_pagado       DECIMAL(10,2) NOT NULL,
    fecha_pago         DATE          NOT NULL DEFAULT GETDATE(),
    metodo_pago        VARCHAR(50)   NOT NULL,
    notas              VARCHAR(255)  NULL,
    CONSTRAINT PK_pago PRIMARY KEY (id_pago),
    CONSTRAINT FK_pago_cliente FOREIGN KEY (id_cliente)
        REFERENCES cliente(id_cliente)
        ON UPDATE CASCADE
        ON DELETE NO ACTION,
    CONSTRAINT FK_pago_compra FOREIGN KEY (id_compra)
        REFERENCES compra(id_compra)
        ON DELETE NO ACTION
        ON UPDATE NO ACTION,
    CONSTRAINT FK_pago_estado FOREIGN KEY (estado_pago)
        REFERENCES estado_pago(id_estado)
        ON UPDATE CASCADE,
    CONSTRAINT CHK_pago_monto CHECK (monto_pagado > 0)
);
GO

-- grupo f: finanzas
-- cuenta_bancaria agrupa ingreso y gastos. El saldo_actual se mantiene
-- actualizado por los procedimientos y triggers; no se recalcula en cada consulta.

-- cuentas bancarias de soul cr (tinyint: máx. 255 cuentas)
CREATE TABLE cuenta_bancaria (
    id_cuenta      TINYINT       NOT NULL,
    tipo_cuenta    VARCHAR(50)   NOT NULL,
    titular        VARCHAR(100)  NOT NULL,
    saldo_actual   DECIMAL(10,2) NOT NULL DEFAULT 0,
    iban           VARCHAR(50)   NULL,
    contacto_banco VARCHAR(30)   NULL,
    estado         INT           NOT NULL DEFAULT 1,
    fecha_apertura DATE          NULL,
    numero_cuenta  VARCHAR(50)   NULL,
    nombre_banco   VARCHAR(50)   NOT NULL,
    CONSTRAINT PK_cuenta_bancaria PRIMARY KEY (id_cuenta),
    CONSTRAINT FK_cuenta_estado FOREIGN KEY (estado)
        REFERENCES estado_cuenta(id_estado),
    CONSTRAINT CHK_cuenta_saldo CHECK (saldo_actual >= 0)
);
GO

-- ingresos monetarios por compra
CREATE TABLE ingreso (
    id_ingreso       INT           NOT NULL IDENTITY(1,1),
    id_compra        INT           NOT NULL,
    id_cuenta        TINYINT       NOT NULL,
    metodo_pago      VARCHAR(50)   NOT NULL,
    monto_ingresado  DECIMAL(10,2) NOT NULL,
    referencia_banco VARCHAR(100)  NULL,
    estado           TINYINT       NOT NULL DEFAULT 2,
    flujo_ingresado  DECIMAL(10,2) NULL,
    fecha_ingreso    DATE          NOT NULL DEFAULT GETDATE(),
    CONSTRAINT PK_ingreso PRIMARY KEY (id_ingreso),
    CONSTRAINT FK_ingreso_compra FOREIGN KEY (id_compra)
        REFERENCES compra(id_compra)
        ON DELETE NO ACTION
        ON UPDATE CASCADE,
    CONSTRAINT FK_ingreso_cuenta FOREIGN KEY (id_cuenta)
        REFERENCES cuenta_bancaria(id_cuenta)
        ON UPDATE CASCADE
        ON DELETE NO ACTION,
    CONSTRAINT FK_ingreso_estado FOREIGN KEY (estado)
        REFERENCES estado_pago(id_estado),
    CONSTRAINT CHK_ingreso_monto CHECK (monto_ingresado > 0)
);
GO

-- egresos operativos de soul cr
CREATE TABLE gastos (
    id_gastos      INT           NOT NULL IDENTITY(1,1),
    id_cuenta      TINYINT       NOT NULL,
    responsable    VARCHAR(100)  NULL,
    fecha_registro DATE          NOT NULL DEFAULT GETDATE(),
    fecha_gasto    DATE          NOT NULL,
    descripcion    VARCHAR(255)  NULL,
    categoria      VARCHAR(100)  NULL,
    monto          tipo_monto    NOT NULL,
    comprobante    VARCHAR(100)  NULL,
    notas          VARCHAR(255)  NULL,
    CONSTRAINT PK_gastos PRIMARY KEY (id_gastos),
    CONSTRAINT FK_gastos_cuenta FOREIGN KEY (id_cuenta)
        REFERENCES cuenta_bancaria(id_cuenta)
        ON UPDATE CASCADE
        ON DELETE NO ACTION,
    CONSTRAINT CHK_gastos_monto CHECK (monto > 0)
);
GO

-- sección 4: valores por defecto
-- Los DEFAULT están definidos directamente en las columnas de cada tabla
-- con nombres explícitos (DF_*) para facilitar su referencia si se necesitan modificar.
-- df_cliente_estado  → cliente.estado_cliente    = 1
-- df_cliente_fecha   → cliente.fecha_registro    = getdate()
-- df_compra_fecha    → compra.fecha_compra       = getdate()
-- df_compra_estado   → compra.estado_pago        = 2
-- df_inventario_unidades → inventario.unidades_vendidas = 0

-- sección 5: índices
-- Índices no agrupados sobre columnas de JOIN y filtrado frecuente.
-- El costo es algo más de espacio en disco y escrituras un poco más lentas,
-- pero las lecturas en los reportes mejoran considerablemente.

-- acelera búsqueda de compras por cliente
CREATE INDEX IDX_compra_cliente   ON compra(id_cliente);
GO

-- acelera reportes de productos más vendidos
CREATE INDEX IDX_detalle_producto ON detalle_compra(id_producto);
GO

-- acelera resumen financiero por cuenta
CREATE INDEX IDX_ingreso_cuenta   ON ingreso(id_cuenta);
GO

-- sección 6: datos de prueba
-- Datos coherentes entre sí: las compras FC-2025-003 y FC-2025-005 están
-- pendientes de pago para poder probar el flujo de confirmación.
-- La geografía usa datos reales de Costa Rica, incluyendo Pital de San Carlos.

-- tablas fn4
INSERT INTO estado_cliente        (id_estado, descripcion) VALUES (1,'activo'),(2,'inactivo'),(3,'suspendido');
GO
INSERT INTO estado_pago           (id_estado, descripcion) VALUES (1,'aplicado'),(2,'pendiente'),(3,'rechazado'),(4,'devuelto');
GO
INSERT INTO estado_cuenta         (id_estado, descripcion) VALUES (1,'activa'),(2,'inactiva'),(3,'bloqueada');
GO
INSERT INTO estado_inventario     (id_estado, descripcion) VALUES (1,'activo'),(2,'descontinuado'),(3,'revision');
GO
INSERT INTO activa_inventario     (id_estado, descripcion) VALUES (1,'Si'),(2,'No');
GO
INSERT INTO disponible_inventario (id_estado, descripcion) VALUES (1,'disponible'),(2,'agotado'),(3,'bajo_pedido');
GO
INSERT INTO disponibilidad_material (id_estado, descripcion) VALUES (1,'disponible'),(2,'no_disponible');
GO

-- geografía de costa rica
INSERT INTO provincias (id_provincia, provincia) VALUES
    (1,'San José'),(2,'Alajuela'),(3,'Cartago'),(4,'Heredia'),
    (5,'Guanacaste'),(6,'Puntarenas'),(7,'Limón');
GO

INSERT INTO cantones (id_canton, canton, provincia) VALUES
    (101,'San José',1),(102,'Escazú',1),(103,'Desamparados',1),
    (201,'Alajuela',2),(202,'San Carlos',2),(203,'Grecia',2),
    (301,'Cartago',3),(302,'Turrialba',3),
    (401,'Heredia',4),(402,'San Rafael',4),
    (501,'Liberia',5),(601,'Puntarenas',6);
GO

INSERT INTO distritos (id_distrito, distrito, canton) VALUES
    (10101,'Carmen',101),(10102,'Merced',101),(10103,'Hospital',101),
    (10201,'Escazú',102),(10202,'San Antonio',102),
    (10301,'Desamparados',103),(10302,'San Miguel',103),
    (20101,'Alajuela',201),(20102,'San José',201),
    (20201,'Quesada',202),(20202,'Florencia',202),(20203,'Pital',202),
    (20301,'Grecia',203),
    (30101,'Oriental',301),(30201,'Turrialba',302),
    (40101,'Heredia',401),(40201,'San Rafael',402),
    (50101,'Liberia',501),(60101,'Puntarenas',601);
GO

-- clientes
INSERT INTO cliente (nombre, apellido1, apellido2, estado_cliente, fecha_registro) VALUES
    ('María José',    'Rodríguez', 'Quesada',  1, '2024-01-15'),
    ('Carlos',        'Méndez',    'Solano',    1, '2024-02-20'),
    ('Daniela',       'Vargas',    'Araya',     1, '2024-03-05'),
    ('Luis Fernando', 'Jiménez',   'Mora',      1, '2024-04-10'),
    ('Andrea',        'Castro',    'Rojas',     2, '2024-05-22'),
    ('Ricardo',       'Ureña',     'Fallas',    1, '2024-06-18'),
    ('Valentina',     'Solís',     'Arias',     1, '2024-07-30'),
    ('Marco Antonio', 'Badilla',   'Herrera',   1, '2024-08-14');
GO

-- emails
INSERT INTO email (id_cliente, email) VALUES
    (1,'mj.rodriguez@gmail.com'),(2,'c.mendez@hotmail.com'),
    (3,'d.vargas@yahoo.com'),(4,'lf.jimenez@gmail.com'),
    (5,'a.castro@outlook.com'),(6,'r.urena@gmail.com'),
    (7,'v.solis@hotmail.com'),(8,'ma.badilla@gmail.com');
GO

-- teléfonos
INSERT INTO telefonos (id_cliente, telefono) VALUES
    (1,'+506 8831-2045'),(2,'+506 7234-5678'),(3,'+506 6123-9876'),
    (4,'+506 8945-3210'),(5,'+506 7756-4433'),(6,'+506 8867-1122'),
    (7,'+506 6398-5500'),(8,'+506 8812-7700');
GO

-- direcciones
INSERT INTO direccion (id_cliente, id_distrito) VALUES
    (1,10101),(2,20203),(3,20201),(4,10201),
    (5,40101),(6,20202),(7,30101),(8,10301);
GO

-- categorías de producto
INSERT INTO categoria_producto (nombre, descripcion, activa, comision_venta) VALUES
    ('Collares','Collares artesanales de distintos materiales',1,10.00),
    ('Anillos','Anillos de compromiso, alianzas y de moda',1,12.00),
    ('Pulseras','Pulseras tejidas y metálicas artesanales',1,8.00),
    ('Aretes','Aretes colgantes, de presión y de argolla',1,9.50);
GO

-- materiales
INSERT INTO tipo_material (nombre_material, proveedor, costo_unitario, densidad, fecha_ultima_actualizacion, descripcion, disponibilidad) VALUES
    ('Acero Inoxidable','MetalesCR S.A.',   45,  7.90,'2025-01-10','Acero 316L resistente a la corrosión',1),
    ('Plata 925',       'JoyasPlata Ltda.',180, 10.49,'2025-02-15','Plata esterlina 92.5% pureza',        1),
    ('Oro 18k',         'OroFino CR',      220, 15.58,'2025-03-01','Oro 18 kilates 75% pureza',           1),
    ('Chapa de Oro',    'MetalesCR S.A.',   60,  8.10,'2025-03-20','Baño de oro sobre base metálica',     1);
GO

-- productos
INSERT INTO producto (id_categoria, nombre, descripcion, precio_venta, codigo, disponibilidad, material, tipo, imagen_url) VALUES
    (1,'Collar Luna de Plata',   'Collar con dije de luna en plata 925',       18500.00,'COL-PLT-001',1,2,'Colgante', NULL),
    (1,'Collar Cadena Oro 18k',  'Cadena fina dorada de 45 cm',                45000.00,'COL-ORO-001',1,3,'Cadena',   NULL),
    (2,'Anillo Solitario Plata', 'Anillo con piedra zirconia en plata 925',    12000.00,'ANI-PLT-001',1,2,'Solitario',NULL),
    (2,'Argolla Acero Unisex',   'Argolla lisa pulida en acero inoxidable',     6500.00,'ANI-ACE-001',1,1,'Argolla',  NULL),
    (3,'Pulsera Eslabones Plata','Pulsera de eslabones en plata 925 de 18 cm', 15000.00,'PUL-PLT-001',1,2,'Eslabones',NULL),
    (3,'Pulsera Chapa Oro',      'Pulsera dorada con dije de corazón',          9800.00,'PUL-CHA-001',1,4,'Colgante', NULL),
    (4,'Aretes Argolla Acero',   'Aretes de argolla en acero inoxidable 2 cm',  4200.00,'ARE-ACE-001',1,1,'Argolla',  NULL),
    (4,'Aretes Luna Plata',      'Aretes colgantes con luna y estrella plata',  8900.00,'ARE-PLT-001',1,2,'Colgante', NULL),
    (1,'Collar Corazón Chapa',   'Collar corazón bañado en oro con cadena',     7500.00,'COL-CHA-001',1,4,'Colgante', NULL),
    (2,'Anillo Oro 18k Clásico', 'Anillo liso en oro 18k talla 7',             35000.00,'ANI-ORO-001',1,3,'Liso',     NULL);
GO

-- inventario
INSERT INTO inventario (id_producto, unidades_vendidas, cantidad_disponible, cantidad_minima, cantidad_maxima, estado) VALUES
    (1,12,25,5,50,1),(2,5,10,3,30,1),(3,20,18,5,40,1),(4,35,42,10,80,1),(5,8,14,5,35,1),
    (6,15,20,5,45,1),(7,50,60,15,100,1),(8,10,12,5,30,1),(9,3,8,5,25,1),(10,2,5,2,15,1);
GO

-- cuentas bancarias
INSERT INTO cuenta_bancaria (id_cuenta, tipo_cuenta, titular, saldo_actual, iban, contacto_banco, estado, fecha_apertura, numero_cuenta, nombre_banco) VALUES
    (1,'Efectivo',        'Soul Cr', 150000.00,NULL,NULL,1,'2023-01-01',NULL,'Caja Chica'),
    (2,'Cuenta Corriente','Soul Cr',2500000.00,'CR21015200009123456789','2290-1234',1,'2023-01-15','15200009123456','Banco Nacional CR');
GO

-- compras
INSERT INTO compra (id_cliente, numero_factura, fecha_compra, monto_total, estado_pago, flujo_ingresos, comentarios) VALUES
    (1,'FC-2025-001','2025-03-10',26900.00,1,26900.00,'Pago completo por transferencia'),
    (2,'FC-2025-002','2025-03-15',45000.00,1,45000.00,'Collar de oro para regalo'),        
    (3,'FC-2025-003','2025-04-01',20900.00,2,NULL,    'Pendiente de confirmación de pago'),
    (4,'FC-2025-004','2025-04-20',18500.00,1,18500.00,'Compra en línea validada'),          
    (6,'FC-2025-005','2025-05-05',16300.00,2,NULL,    'Esperando transferencia del cliente')
GO

-- detalle de compras
INSERT INTO detalle_compra (id_compra, id_producto, cantidad, precio_unitario) VALUES (1,1,1,18500.00),(1,7,2,4200.00);
GO
INSERT INTO detalle_compra (id_compra, id_producto, cantidad, precio_unitario) VALUES (2,2,1,45000.00);
GO
INSERT INTO detalle_compra (id_compra, id_producto, cantidad, precio_unitario) VALUES (3,3,1,12000.00),(3,8,1,8900.00);
GO
INSERT INTO detalle_compra (id_compra, id_producto, cantidad, precio_unitario) VALUES (4,1,1,18500.00);
GO
INSERT INTO detalle_compra (id_compra, id_producto, cantidad, precio_unitario) VALUES (5,6,1,9800.00),(5,4,1,6500.00);
GO

-- pagos
INSERT INTO pago (id_cliente, id_compra, numero_referencia, estado_pago, numero_comprobante, monto_pagado, fecha_pago, metodo_pago, notas) VALUES
    (1,1,'REF-SINPE-00123',1,'COMP-001',26900.00,'2025-03-10','SINPE Móvil',        'Pago confirmado por SINPE'), 
    (2,2,'REF-BN-00456',   1,'COMP-002',45000.00,'2025-03-15','Transferencia Banco','Transferencia Banco Nacional'), 
    (4,4,'REF-SINPE-00789',1,'COMP-003',18500.00,'2025-04-20','SINPE Móvil',        'Pago recibido correctamente');  
GO

-- ingresos
INSERT INTO ingreso (id_compra, id_cuenta, metodo_pago, monto_ingresado, referencia_banco, estado, flujo_ingresado, fecha_ingreso) VALUES
    (1,2,'SINPE Móvil',        26900.00,'SINPE-2025-00123',1,26900.00,'2025-03-10'), 
    (2,2,'Transferencia Banco',45000.00,'BN-2025-00456',   1,45000.00,'2025-03-15'), 
    (4,2,'SINPE Móvil',        18500.00,'SINPE-2025-00789',1,18500.00,'2025-04-20'); 
GO

-- gastos
INSERT INTO gastos (id_cuenta, responsable, fecha_registro, fecha_gasto, descripcion, categoria, monto, comprobante, notas) VALUES
    (1,'Ana Solís Rojas', '2025-03-01','2025-03-01','Compra de materiales: plata 925 50g',   'Materia Prima',18000.00,'FACT-MAT-001','Para producción de collares del mes'),
    (2,'Ricardo Ureña',   '2025-04-05','2025-04-05','Pago de plataforma de ventas en línea', 'Tecnología',    9500.00,'FACT-TEC-002','Suscripción mensual plataforma e-commerce'),
    (1,'María Rodríguez', '2025-05-02','2025-05-02','Empaque y materiales de envío abril',   'Logística',     5200.00,'FACT-LOG-003','Cajas, papel burbuja y cintas para envíos');
GO

-- =============================================================================
-- sección 7 y 8: procedimientos CRUD
-- Patrón uniforme en los 96 procedimientos:
--   • SET NOCOUNT ON para no emitir mensajes de conteo innecesarios.
--   • Validaciones de NULL y existencia antes de tocar la DB.
--   • TRY/CATCH con THROW para propagar el error al llamador.
--   • El insertar retorna la fila creada; el actualizar retorna @@ROWCOUNT.
-- =============================================================================

-- crud: estado_cliente

-- inserta un estado de cliente
CREATE OR ALTER PROCEDURE sp_insertar_estado_cliente
    @id_estado   INT,
    @descripcion VARCHAR(20)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        IF @id_estado   IS NULL RAISERROR('id_estado no puede ser NULL.',16,1);
        IF @descripcion IS NULL RAISERROR('descripcion no puede ser NULL.',16,1);
        IF EXISTS (SELECT 1 FROM estado_cliente WHERE id_estado = @id_estado)
            RAISERROR('El id_estado %d ya existe en estado_cliente.',16,1,@id_estado);
        INSERT INTO estado_cliente (id_estado, descripcion) VALUES (@id_estado, @descripcion);
        SELECT * FROM estado_cliente WHERE id_estado = @id_estado;
    END TRY
    BEGIN CATCH
        THROW;
    END CATCH
END;
GO

-- actualiza la descripción de un estado de cliente
CREATE OR ALTER PROCEDURE sp_actualizar_estado_cliente
    @id_estado   INT,
    @descripcion VARCHAR(20)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM estado_cliente WHERE id_estado = @id_estado)
            RAISERROR('No existe estado_cliente con id_estado %d.',16,1,@id_estado);
        UPDATE estado_cliente SET descripcion = @descripcion WHERE id_estado = @id_estado;
        SELECT @@ROWCOUNT AS filas_afectadas;
    END TRY
    BEGIN CATCH
        THROW;
    END CATCH
END;
GO

-- elimina un estado de cliente
CREATE OR ALTER PROCEDURE sp_eliminar_estado_cliente
    @id_estado INT
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM estado_cliente WHERE id_estado = @id_estado)
            RAISERROR('No existe estado_cliente con id_estado %d.',16,1,@id_estado);
        DELETE FROM estado_cliente WHERE id_estado = @id_estado;
        SELECT 'Estado de cliente eliminado correctamente.' AS mensaje;
    END TRY
    BEGIN CATCH
        THROW;
    END CATCH
END;
GO

-- consulta uno o todos los estados de cliente
CREATE OR ALTER PROCEDURE sp_consultar_estado_cliente
    @id_estado INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        IF @id_estado IS NULL
            SELECT * FROM estado_cliente ORDER BY id_estado;
        ELSE
            SELECT * FROM estado_cliente WHERE id_estado = @id_estado;
    END TRY
    BEGIN CATCH
        THROW;
    END CATCH
END;
GO

-- crud: estado_pago

-- inserta un estado de pago
CREATE OR ALTER PROCEDURE sp_insertar_estado_pago
    @id_estado   INT,
    @descripcion VARCHAR(20)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        IF @id_estado   IS NULL RAISERROR('id_estado no puede ser NULL.',16,1);
        IF @descripcion IS NULL RAISERROR('descripcion no puede ser NULL.',16,1);
        IF EXISTS (SELECT 1 FROM estado_pago WHERE id_estado = @id_estado)
            RAISERROR('El id_estado %d ya existe en estado_pago.',16,1,@id_estado);
        INSERT INTO estado_pago (id_estado, descripcion) VALUES (@id_estado, @descripcion);
        SELECT * FROM estado_pago WHERE id_estado = @id_estado;
    END TRY
    BEGIN CATCH
        THROW;
    END CATCH
END;
GO

-- actualiza la descripción de un estado de pago
CREATE OR ALTER PROCEDURE sp_actualizar_estado_pago
    @id_estado   INT,
    @descripcion VARCHAR(20)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM estado_pago WHERE id_estado = @id_estado)
            RAISERROR('No existe estado_pago con id_estado %d.',16,1,@id_estado);
        UPDATE estado_pago SET descripcion = @descripcion WHERE id_estado = @id_estado;
        SELECT @@ROWCOUNT AS filas_afectadas;
    END TRY
    BEGIN CATCH
        THROW;
    END CATCH
END;
GO

-- elimina un estado de pago
CREATE OR ALTER PROCEDURE sp_eliminar_estado_pago
    @id_estado INT
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM estado_pago WHERE id_estado = @id_estado)
            RAISERROR('No existe estado_pago con id_estado %d.',16,1,@id_estado);
        DELETE FROM estado_pago WHERE id_estado = @id_estado;
        SELECT 'Estado de pago eliminado correctamente.' AS mensaje;
    END TRY
    BEGIN CATCH
        THROW;
    END CATCH
END;
GO

-- consulta uno o todos los estados de pago
CREATE OR ALTER PROCEDURE sp_consultar_estado_pago
    @id_estado INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        IF @id_estado IS NULL
            SELECT * FROM estado_pago ORDER BY id_estado;
        ELSE
            SELECT * FROM estado_pago WHERE id_estado = @id_estado;
    END TRY
    BEGIN CATCH
        THROW;
    END CATCH
END;
GO

-- crud: estado_cuenta

-- inserta un estado de cuenta bancaria
CREATE OR ALTER PROCEDURE sp_insertar_estado_cuenta
    @id_estado   INT,
    @descripcion VARCHAR(20)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        IF @id_estado   IS NULL RAISERROR('id_estado no puede ser NULL.',16,1);
        IF @descripcion IS NULL RAISERROR('descripcion no puede ser NULL.',16,1);
        IF EXISTS (SELECT 1 FROM estado_cuenta WHERE id_estado = @id_estado)
            RAISERROR('El id_estado %d ya existe en estado_cuenta.',16,1,@id_estado);
        INSERT INTO estado_cuenta (id_estado, descripcion) VALUES (@id_estado, @descripcion);
        SELECT * FROM estado_cuenta WHERE id_estado = @id_estado;
    END TRY
    BEGIN CATCH
        THROW;
    END CATCH
END;
GO

-- actualiza la descripción de un estado de cuenta
CREATE OR ALTER PROCEDURE sp_actualizar_estado_cuenta
    @id_estado   INT,
    @descripcion VARCHAR(20)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM estado_cuenta WHERE id_estado = @id_estado)
            RAISERROR('No existe estado_cuenta con id_estado %d.',16,1,@id_estado);
        UPDATE estado_cuenta SET descripcion = @descripcion WHERE id_estado = @id_estado;
        SELECT @@ROWCOUNT AS filas_afectadas;
    END TRY
    BEGIN CATCH
        THROW;
    END CATCH
END;
GO

-- elimina un estado de cuenta
CREATE OR ALTER PROCEDURE sp_eliminar_estado_cuenta
    @id_estado INT
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM estado_cuenta WHERE id_estado = @id_estado)
            RAISERROR('No existe estado_cuenta con id_estado %d.',16,1,@id_estado);
        DELETE FROM estado_cuenta WHERE id_estado = @id_estado;
        SELECT 'Estado de cuenta eliminado correctamente.' AS mensaje;
    END TRY
    BEGIN CATCH
        THROW;
    END CATCH
END;
GO

-- consulta uno o todos los estados de cuenta
CREATE OR ALTER PROCEDURE sp_consultar_estado_cuenta
    @id_estado INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        IF @id_estado IS NULL
            SELECT * FROM estado_cuenta ORDER BY id_estado;
        ELSE
            SELECT * FROM estado_cuenta WHERE id_estado = @id_estado;
    END TRY
    BEGIN CATCH
        THROW;
    END CATCH
END;
GO

-- crud: estado_inventario

-- inserta un estado de inventario
CREATE OR ALTER PROCEDURE sp_insertar_estado_inventario
    @id_estado   INT,
    @descripcion VARCHAR(20)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        IF @id_estado   IS NULL RAISERROR('id_estado no puede ser NULL.',16,1);
        IF @descripcion IS NULL RAISERROR('descripcion no puede ser NULL.',16,1);
        IF EXISTS (SELECT 1 FROM estado_inventario WHERE id_estado = @id_estado)
            RAISERROR('El id_estado %d ya existe en estado_inventario.',16,1,@id_estado);
        INSERT INTO estado_inventario (id_estado, descripcion) VALUES (@id_estado, @descripcion);
        SELECT * FROM estado_inventario WHERE id_estado = @id_estado;
    END TRY
    BEGIN CATCH
        THROW;
    END CATCH
END;
GO

-- actualiza la descripción de un estado de inventario
CREATE OR ALTER PROCEDURE sp_actualizar_estado_inventario
    @id_estado   INT,
    @descripcion VARCHAR(20)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM estado_inventario WHERE id_estado = @id_estado)
            RAISERROR('No existe estado_inventario con id_estado %d.',16,1,@id_estado);
        UPDATE estado_inventario SET descripcion = @descripcion WHERE id_estado = @id_estado;
        SELECT @@ROWCOUNT AS filas_afectadas;
    END TRY
    BEGIN CATCH
        THROW;
    END CATCH
END;
GO

-- elimina un estado de inventario
CREATE OR ALTER PROCEDURE sp_eliminar_estado_inventario
    @id_estado INT
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM estado_inventario WHERE id_estado = @id_estado)
            RAISERROR('No existe estado_inventario con id_estado %d.',16,1,@id_estado);
        DELETE FROM estado_inventario WHERE id_estado = @id_estado;
        SELECT 'Estado de inventario eliminado correctamente.' AS mensaje;
    END TRY
    BEGIN CATCH
        THROW;
    END CATCH
END;
GO

-- consulta uno o todos los estados de inventario
CREATE OR ALTER PROCEDURE sp_consultar_estado_inventario
    @id_estado INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        IF @id_estado IS NULL
            SELECT * FROM estado_inventario ORDER BY id_estado;
        ELSE
            SELECT * FROM estado_inventario WHERE id_estado = @id_estado;
    END TRY
    BEGIN CATCH
        THROW;
    END CATCH
END;
GO

-- crud: activa_inventario

-- inserta un valor de activación de inventario
CREATE OR ALTER PROCEDURE sp_insertar_activa_inventario
    @id_estado   INT,
    @descripcion VARCHAR(20)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        IF @id_estado   IS NULL RAISERROR('id_estado no puede ser NULL.',16,1);
        IF @descripcion IS NULL RAISERROR('descripcion no puede ser NULL.',16,1);
        IF EXISTS (SELECT 1 FROM activa_inventario WHERE id_estado = @id_estado)
            RAISERROR('El id_estado %d ya existe en activa_inventario.',16,1,@id_estado);
        INSERT INTO activa_inventario (id_estado, descripcion) VALUES (@id_estado, @descripcion);
        SELECT * FROM activa_inventario WHERE id_estado = @id_estado;
    END TRY
    BEGIN CATCH
        THROW;
    END CATCH
END;
GO

-- actualiza la descripción de activa_inventario
CREATE OR ALTER PROCEDURE sp_actualizar_activa_inventario
    @id_estado   INT,
    @descripcion VARCHAR(20)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM activa_inventario WHERE id_estado = @id_estado)
            RAISERROR('No existe activa_inventario con id_estado %d.',16,1,@id_estado);
        UPDATE activa_inventario SET descripcion = @descripcion WHERE id_estado = @id_estado;
        SELECT @@ROWCOUNT AS filas_afectadas;
    END TRY
    BEGIN CATCH
        THROW;
    END CATCH
END;
GO

-- elimina un registro de activa_inventario
CREATE OR ALTER PROCEDURE sp_eliminar_activa_inventario
    @id_estado INT
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM activa_inventario WHERE id_estado = @id_estado)
            RAISERROR('No existe activa_inventario con id_estado %d.',16,1,@id_estado);
        DELETE FROM activa_inventario WHERE id_estado = @id_estado;
        SELECT 'Registro de activa_inventario eliminado correctamente.' AS mensaje;
    END TRY
    BEGIN CATCH
        THROW;
    END CATCH
END;
GO

-- consulta uno o todos los registros de activa_inventario
CREATE OR ALTER PROCEDURE sp_consultar_activa_inventario
    @id_estado INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        IF @id_estado IS NULL
            SELECT * FROM activa_inventario ORDER BY id_estado;
        ELSE
            SELECT * FROM activa_inventario WHERE id_estado = @id_estado;
    END TRY
    BEGIN CATCH
        THROW;
    END CATCH
END;
GO

-- crud: disponible_inventario

-- inserta un valor de disponibilidad de inventario
CREATE OR ALTER PROCEDURE sp_insertar_disponible_inventario
    @id_estado   INT,
    @descripcion VARCHAR(20)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        IF @id_estado   IS NULL RAISERROR('id_estado no puede ser NULL.',16,1);
        IF @descripcion IS NULL RAISERROR('descripcion no puede ser NULL.',16,1);
        IF EXISTS (SELECT 1 FROM disponible_inventario WHERE id_estado = @id_estado)
            RAISERROR('El id_estado %d ya existe en disponible_inventario.',16,1,@id_estado);
        INSERT INTO disponible_inventario (id_estado, descripcion) VALUES (@id_estado, @descripcion);
        SELECT * FROM disponible_inventario WHERE id_estado = @id_estado;
    END TRY
    BEGIN CATCH
        THROW;
    END CATCH
END;
GO

-- actualiza la descripción de disponible_inventario
CREATE OR ALTER PROCEDURE sp_actualizar_disponible_inventario
    @id_estado   INT,
    @descripcion VARCHAR(20)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM disponible_inventario WHERE id_estado = @id_estado)
            RAISERROR('No existe disponible_inventario con id_estado %d.',16,1,@id_estado);
        UPDATE disponible_inventario SET descripcion = @descripcion WHERE id_estado = @id_estado;
        SELECT @@ROWCOUNT AS filas_afectadas;
    END TRY
    BEGIN CATCH
        THROW;
    END CATCH
END;
GO

-- elimina un registro de disponible_inventario
CREATE OR ALTER PROCEDURE sp_eliminar_disponible_inventario
    @id_estado INT
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM disponible_inventario WHERE id_estado = @id_estado)
            RAISERROR('No existe disponible_inventario con id_estado %d.',16,1,@id_estado);
        DELETE FROM disponible_inventario WHERE id_estado = @id_estado;
        SELECT 'Registro de disponible_inventario eliminado correctamente.' AS mensaje;
    END TRY
    BEGIN CATCH
        THROW;
    END CATCH
END;
GO

-- consulta uno o todos los registros de disponible_inventario
CREATE OR ALTER PROCEDURE sp_consultar_disponible_inventario
    @id_estado INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        IF @id_estado IS NULL
            SELECT * FROM disponible_inventario ORDER BY id_estado;
        ELSE
            SELECT * FROM disponible_inventario WHERE id_estado = @id_estado;
    END TRY
    BEGIN CATCH
        THROW;
    END CATCH
END;
GO

-- crud: disponibilidad_material

-- inserta un valor de disponibilidad de material
CREATE OR ALTER PROCEDURE sp_insertar_disponibilidad_material
    @id_estado   INT,
    @descripcion VARCHAR(20)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        IF @id_estado   IS NULL RAISERROR('id_estado no puede ser NULL.',16,1);
        IF @descripcion IS NULL RAISERROR('descripcion no puede ser NULL.',16,1);
        IF EXISTS (SELECT 1 FROM disponibilidad_material WHERE id_estado = @id_estado)
            RAISERROR('El id_estado %d ya existe en disponibilidad_material.',16,1,@id_estado);
        INSERT INTO disponibilidad_material (id_estado, descripcion) VALUES (@id_estado, @descripcion);
        SELECT * FROM disponibilidad_material WHERE id_estado = @id_estado;
    END TRY
    BEGIN CATCH
        THROW;
    END CATCH
END;
GO

-- actualiza la descripción de disponibilidad_material
CREATE OR ALTER PROCEDURE sp_actualizar_disponibilidad_material
    @id_estado   INT,
    @descripcion VARCHAR(20)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM disponibilidad_material WHERE id_estado = @id_estado)
            RAISERROR('No existe disponibilidad_material con id_estado %d.',16,1,@id_estado);
        UPDATE disponibilidad_material SET descripcion = @descripcion WHERE id_estado = @id_estado;
        SELECT @@ROWCOUNT AS filas_afectadas;
    END TRY
    BEGIN CATCH
        THROW;
    END CATCH
END;
GO

-- elimina un registro de disponibilidad_material
CREATE OR ALTER PROCEDURE sp_eliminar_disponibilidad_material
    @id_estado INT
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM disponibilidad_material WHERE id_estado = @id_estado)
            RAISERROR('No existe disponibilidad_material con id_estado %d.',16,1,@id_estado);
        DELETE FROM disponibilidad_material WHERE id_estado = @id_estado;
        SELECT 'Registro de disponibilidad_material eliminado correctamente.' AS mensaje;
    END TRY
    BEGIN CATCH
        THROW;
    END CATCH
END;
GO

-- consulta uno o todos los registros de disponibilidad_material
CREATE OR ALTER PROCEDURE sp_consultar_disponibilidad_material
    @id_estado INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        IF @id_estado IS NULL
            SELECT * FROM disponibilidad_material ORDER BY id_estado;
        ELSE
            SELECT * FROM disponibilidad_material WHERE id_estado = @id_estado;
    END TRY
    BEGIN CATCH
        THROW;
    END CATCH
END;
GO

-- crud: provincias

-- inserta una provincia
CREATE OR ALTER PROCEDURE sp_insertar_provincias
    @id_provincia TINYINT,
    @provincia    VARCHAR(15)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        IF @id_provincia IS NULL RAISERROR('id_provincia no puede ser NULL.',16,1);
        IF @provincia    IS NULL RAISERROR('provincia no puede ser NULL.',16,1);
        IF EXISTS (SELECT 1 FROM provincias WHERE id_provincia = @id_provincia)
            RAISERROR('El id_provincia %d ya existe.',16,1,@id_provincia);
        INSERT INTO provincias (id_provincia, provincia) VALUES (@id_provincia, @provincia);
        SELECT * FROM provincias WHERE id_provincia = @id_provincia;
    END TRY
    BEGIN CATCH
        THROW;
    END CATCH
END;
GO

-- actualiza el nombre de una provincia
CREATE OR ALTER PROCEDURE sp_actualizar_provincias
    @id_provincia TINYINT,
    @provincia    VARCHAR(15)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM provincias WHERE id_provincia = @id_provincia)
            RAISERROR('No existe provincia con id_provincia %d.',16,1,@id_provincia);
        UPDATE provincias SET provincia = @provincia WHERE id_provincia = @id_provincia;
        SELECT @@ROWCOUNT AS filas_afectadas;
    END TRY
    BEGIN CATCH
        THROW;
    END CATCH
END;
GO

-- elimina una provincia
CREATE OR ALTER PROCEDURE sp_eliminar_provincias
    @id_provincia TINYINT
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM provincias WHERE id_provincia = @id_provincia)
            RAISERROR('No existe provincia con id_provincia %d.',16,1,@id_provincia);
        DELETE FROM provincias WHERE id_provincia = @id_provincia;
        SELECT 'Provincia eliminada correctamente.' AS mensaje;
    END TRY
    BEGIN CATCH
        THROW;
    END CATCH
END;
GO

-- consulta una o todas las provincias
CREATE OR ALTER PROCEDURE sp_consultar_provincias
    @id_provincia TINYINT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        IF @id_provincia IS NULL
            SELECT * FROM provincias ORDER BY id_provincia;
        ELSE
            SELECT * FROM provincias WHERE id_provincia = @id_provincia;
    END TRY
    BEGIN CATCH
        THROW;
    END CATCH
END;
GO

-- crud: cantones

-- inserta un cantón con su provincia
CREATE OR ALTER PROCEDURE sp_insertar_cantones
    @id_canton SMALLINT,
    @canton    VARCHAR(15),
    @provincia TINYINT
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        IF @id_canton IS NULL RAISERROR('id_canton no puede ser NULL.',16,1);
        IF @canton    IS NULL RAISERROR('canton no puede ser NULL.',16,1);
        IF @provincia IS NULL RAISERROR('provincia no puede ser NULL.',16,1);
        IF EXISTS (SELECT 1 FROM cantones WHERE id_canton = @id_canton)
            RAISERROR('El id_canton %d ya existe.',16,1,@id_canton);
        INSERT INTO cantones (id_canton, canton, provincia) VALUES (@id_canton, @canton, @provincia);
        SELECT c.id_canton, c.canton, c.provincia, p.provincia AS nombre_provincia
        FROM   cantones c
        JOIN   provincias p ON p.id_provincia = c.provincia
        WHERE  c.id_canton = @id_canton;
    END TRY
    BEGIN CATCH
        THROW;
    END CATCH
END;
GO

-- actualiza nombre y provincia de un cantón
CREATE OR ALTER PROCEDURE sp_actualizar_cantones
    @id_canton SMALLINT,
    @canton    VARCHAR(15),
    @provincia TINYINT
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM cantones WHERE id_canton = @id_canton)
            RAISERROR('No existe cantón con id_canton %d.',16,1,@id_canton);
        UPDATE cantones SET canton = @canton, provincia = @provincia WHERE id_canton = @id_canton;
        SELECT @@ROWCOUNT AS filas_afectadas;
    END TRY
    BEGIN CATCH
        THROW;
    END CATCH
END;
GO

-- elimina un cantón
CREATE OR ALTER PROCEDURE sp_eliminar_cantones
    @id_canton SMALLINT
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM cantones WHERE id_canton = @id_canton)
            RAISERROR('No existe cantón con id_canton %d.',16,1,@id_canton);
        DELETE FROM cantones WHERE id_canton = @id_canton;
        SELECT 'Cantón eliminado correctamente.' AS mensaje;
    END TRY
    BEGIN CATCH
        THROW;
    END CATCH
END;
GO

-- consulta cantones con nombre de provincia
CREATE OR ALTER PROCEDURE sp_consultar_cantones
    @id_canton SMALLINT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        IF @id_canton IS NULL
            SELECT c.id_canton, c.canton, c.provincia, p.provincia AS nombre_provincia
            FROM   cantones c
            JOIN   provincias p ON p.id_provincia = c.provincia
            ORDER BY c.id_canton;
        ELSE
            SELECT c.id_canton, c.canton, c.provincia, p.provincia AS nombre_provincia
            FROM   cantones c
            JOIN   provincias p ON p.id_provincia = c.provincia
            WHERE  c.id_canton = @id_canton;
    END TRY
    BEGIN CATCH
        THROW;
    END CATCH
END;
GO

-- crud: distritos

-- inserta un distrito con su cantón
CREATE OR ALTER PROCEDURE sp_insertar_distritos
    @id_distrito INT,
    @distrito    VARCHAR(20),
    @canton      SMALLINT
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        IF @id_distrito IS NULL RAISERROR('id_distrito no puede ser NULL.',16,1);
        IF @distrito    IS NULL RAISERROR('distrito no puede ser NULL.',16,1);
        IF @canton      IS NULL RAISERROR('canton no puede ser NULL.',16,1);
        IF EXISTS (SELECT 1 FROM distritos WHERE id_distrito = @id_distrito)
            RAISERROR('El id_distrito %d ya existe.',16,1,@id_distrito);
        INSERT INTO distritos (id_distrito, distrito, canton) VALUES (@id_distrito, @distrito, @canton);
        SELECT d.id_distrito, d.distrito, d.canton,
               c.canton    AS nombre_canton,
               p.provincia AS nombre_provincia
        FROM   distritos  d
        JOIN   cantones   c ON c.id_canton    = d.canton
        JOIN   provincias p ON p.id_provincia = c.provincia
        WHERE  d.id_distrito = @id_distrito;
    END TRY
    BEGIN CATCH
        THROW;
    END CATCH
END;
GO

-- actualiza nombre y cantón de un distrito
CREATE OR ALTER PROCEDURE sp_actualizar_distritos
    @id_distrito INT,
    @distrito    VARCHAR(20),
    @canton      SMALLINT
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM distritos WHERE id_distrito = @id_distrito)
            RAISERROR('No existe distrito con id_distrito %d.',16,1,@id_distrito);
        UPDATE distritos SET distrito = @distrito, canton = @canton WHERE id_distrito = @id_distrito;
        SELECT @@ROWCOUNT AS filas_afectadas;
    END TRY
    BEGIN CATCH
        THROW;
    END CATCH
END;
GO

-- elimina un distrito
CREATE OR ALTER PROCEDURE sp_eliminar_distritos
    @id_distrito INT
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM distritos WHERE id_distrito = @id_distrito)
            RAISERROR('No existe distrito con id_distrito %d.',16,1,@id_distrito);
        DELETE FROM distritos WHERE id_distrito = @id_distrito;
        SELECT 'Distrito eliminado correctamente.' AS mensaje;
    END TRY
    BEGIN CATCH
        THROW;
    END CATCH
END;
GO

-- consulta distritos con cantón y provincia
CREATE OR ALTER PROCEDURE sp_consultar_distritos
    @id_distrito INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        IF @id_distrito IS NULL
            SELECT d.id_distrito, d.distrito, d.canton,
                   c.canton    AS nombre_canton,
                   p.provincia AS nombre_provincia
            FROM   distritos  d
            JOIN   cantones   c ON c.id_canton    = d.canton
            JOIN   provincias p ON p.id_provincia = c.provincia
            ORDER BY d.id_distrito;
        ELSE
            SELECT d.id_distrito, d.distrito, d.canton,
                   c.canton    AS nombre_canton,
                   p.provincia AS nombre_provincia
            FROM   distritos  d
            JOIN   cantones   c ON c.id_canton    = d.canton
            JOIN   provincias p ON p.id_provincia = c.provincia
            WHERE  d.id_distrito = @id_distrito;
    END TRY
    BEGIN CATCH
        THROW;
    END CATCH
END;
GO



-- crud: cliente
-- Los procedimientos de cliente incluyen validación de FK hacia estado_cliente.
-- sp_insertar usa SCOPE_IDENTITY() para retornar el registro recién creado.

-- inserta un cliente nuevo con validaciones de campos obligatorios y estado
CREATE OR ALTER PROCEDURE sp_insertar_cliente
    @nombre         tipo_nombre_persona,
    @apellido1      tipo_nombre_persona,
    @apellido2      VARCHAR(20) = NULL,
    @estado_cliente TINYINT     = 1,
    @fecha_registro DATE        = NULL
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        -- validaciones de nulos separadas, igual que el codigo base
        IF @nombre    IS NULL RAISERROR('nombre no puede ser NULL.',16,1);
        IF @apellido1 IS NULL RAISERROR('apellido1 no puede ser NULL.',16,1);
        -- valida que el estado referenciado exista en estado_cliente
        IF NOT EXISTS (SELECT 1 FROM estado_cliente WHERE id_estado = @estado_cliente)
            RAISERROR('El estado_cliente %d no existe en estado_cliente.',16,1,@estado_cliente);
        IF @fecha_registro IS NULL SET @fecha_registro = GETDATE();

        INSERT INTO cliente (nombre, apellido1, apellido2, estado_cliente, fecha_registro)
        VALUES (@nombre, @apellido1, @apellido2, @estado_cliente, @fecha_registro);

        SELECT * FROM cliente WHERE id_cliente = SCOPE_IDENTITY();
    END TRY
    BEGIN CATCH THROW; END CATCH
END;
GO

-- actualiza nombre, apellidos y estado de un cliente existente
CREATE OR ALTER PROCEDURE sp_actualizar_cliente
    @id_cliente     INT,
    @nombre         tipo_nombre_persona,
    @apellido1      tipo_nombre_persona,
    @apellido2      VARCHAR(20) = NULL,
    @estado_cliente TINYINT
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM cliente WHERE id_cliente = @id_cliente)
            RAISERROR('No existe cliente con id_cliente %d.',16,1,@id_cliente);
        IF NOT EXISTS (SELECT 1 FROM estado_cliente WHERE id_estado = @estado_cliente)
            RAISERROR('El estado_cliente %d no existe en estado_cliente.',16,1,@estado_cliente);

        UPDATE cliente
        SET nombre = @nombre, apellido1 = @apellido1, apellido2 = @apellido2, estado_cliente = @estado_cliente
        WHERE id_cliente = @id_cliente;

        SELECT @@ROWCOUNT AS filas_afectadas;
    END TRY
    BEGIN CATCH THROW; END CATCH
END;
GO

-- elimina un cliente por su id
CREATE OR ALTER PROCEDURE sp_eliminar_cliente
    @id_cliente INT
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM cliente WHERE id_cliente = @id_cliente)
            RAISERROR('No existe cliente con id_cliente %d.',16,1,@id_cliente);

        DELETE FROM cliente WHERE id_cliente = @id_cliente;
        SELECT 'Cliente eliminado correctamente.' AS mensaje;
    END TRY
    BEGIN CATCH THROW; END CATCH
END;
GO

-- consulta uno o todos los clientes
CREATE OR ALTER PROCEDURE sp_consultar_cliente
    @id_cliente INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        IF @id_cliente IS NULL
            SELECT * FROM cliente ORDER BY id_cliente;
        ELSE
            SELECT * FROM cliente WHERE id_cliente = @id_cliente;
    END TRY
    BEGIN CATCH THROW; END CATCH
END;
GO

-- ---- crud: email ----

-- inserta un email para un cliente existente
CREATE OR ALTER PROCEDURE sp_insertar_email
    @id_cliente INT,
    @email      tipo_email
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        IF @id_cliente IS NULL RAISERROR('id_cliente no puede ser NULL.',16,1);
        IF @email      IS NULL RAISERROR('email no puede ser NULL.',16,1);
        -- valida que el cliente referenciado exista
        IF NOT EXISTS (SELECT 1 FROM cliente WHERE id_cliente = @id_cliente)
            RAISERROR('No existe cliente con id_cliente %d.',16,1,@id_cliente);

        INSERT INTO email (id_cliente, email) VALUES (@id_cliente, @email);
        SELECT * FROM email WHERE id_email = SCOPE_IDENTITY();
    END TRY
    BEGIN CATCH THROW; END CATCH
END;
GO

-- actualiza la direccion de email de un registro existente
CREATE OR ALTER PROCEDURE sp_actualizar_email
    @id_email INT,
    @email    tipo_email
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM email WHERE id_email = @id_email)
            RAISERROR('No existe email con id_email %d.',16,1,@id_email);

        UPDATE email SET email = @email WHERE id_email = @id_email;
        SELECT @@ROWCOUNT AS filas_afectadas;
    END TRY
    BEGIN CATCH THROW; END CATCH
END;
GO

-- elimina un email por su id
CREATE OR ALTER PROCEDURE sp_eliminar_email
    @id_email INT
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM email WHERE id_email = @id_email)
            RAISERROR('No existe email con id_email %d.',16,1,@id_email);

        DELETE FROM email WHERE id_email = @id_email;
        SELECT 'Email eliminado correctamente.' AS mensaje;
    END TRY
    BEGIN CATCH THROW; END CATCH
END;
GO

-- consulta uno o todos los emails; si se pasa id_cliente retorna todos los de ese cliente
CREATE OR ALTER PROCEDURE sp_consultar_email
    @id_email   INT = NULL,
    @id_cliente INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        IF @id_email IS NOT NULL
            SELECT * FROM email WHERE id_email = @id_email;
        ELSE IF @id_cliente IS NOT NULL
            SELECT * FROM email WHERE id_cliente = @id_cliente ORDER BY id_email;
        ELSE
            SELECT * FROM email ORDER BY id_email;
    END TRY
    BEGIN CATCH THROW; END CATCH
END;
GO

-- ---- crud: telefonos ----

-- inserta el telefono de un cliente (uno por cliente, pk en id_cliente)
CREATE OR ALTER PROCEDURE sp_insertar_telefonos
    @id_cliente INT,
    @telefono   tipo_telefono
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        IF @id_cliente IS NULL RAISERROR('id_cliente no puede ser NULL.',16,1);
        IF @telefono   IS NULL RAISERROR('telefono no puede ser NULL.',16,1);
        IF NOT EXISTS (SELECT 1 FROM cliente WHERE id_cliente = @id_cliente)
            RAISERROR('No existe cliente con id_cliente %d.',16,1,@id_cliente);
        IF EXISTS (SELECT 1 FROM telefonos WHERE id_cliente = @id_cliente)
            RAISERROR('El cliente %d ya tiene un telefono registrado.',16,1,@id_cliente);

        INSERT INTO telefonos (id_cliente, telefono) VALUES (@id_cliente, @telefono);
        SELECT * FROM telefonos WHERE id_cliente = @id_cliente;
    END TRY
    BEGIN CATCH THROW; END CATCH
END;
GO

-- actualiza el numero de telefono de un cliente existente
CREATE OR ALTER PROCEDURE sp_actualizar_telefonos
    @id_cliente INT,
    @telefono   tipo_telefono
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM telefonos WHERE id_cliente = @id_cliente)
            RAISERROR('No existe telefono para el id_cliente %d.',16,1,@id_cliente);

        UPDATE telefonos SET telefono = @telefono WHERE id_cliente = @id_cliente;
        SELECT @@ROWCOUNT AS filas_afectadas;
    END TRY
    BEGIN CATCH THROW; END CATCH
END;
GO

-- elimina el telefono de un cliente
CREATE OR ALTER PROCEDURE sp_eliminar_telefonos
    @id_cliente INT
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM telefonos WHERE id_cliente = @id_cliente)
            RAISERROR('No existe telefono para el id_cliente %d.',16,1,@id_cliente);

        DELETE FROM telefonos WHERE id_cliente = @id_cliente;
        SELECT 'Telefono eliminado correctamente.' AS mensaje;
    END TRY
    BEGIN CATCH THROW; END CATCH
END;
GO

-- consulta telefonos; filtra por cliente si se indica
CREATE OR ALTER PROCEDURE sp_consultar_telefonos
    @id_cliente INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        IF @id_cliente IS NULL
            SELECT * FROM telefonos ORDER BY id_cliente;
        ELSE
            SELECT * FROM telefonos WHERE id_cliente = @id_cliente;
    END TRY
    BEGIN CATCH THROW; END CATCH
END;
GO

-- ---- crud: direccion ----
-- PK compuesta (id_cliente, id_distrito): no hay id_direccion propio.
-- sp_actualizar hace DELETE + INSERT del nuevo distrito en vez de UPDATE,
-- porque cambiar parte de la PK requiere reemplazar la fila completa.; actualizar = delete + insert del nuevo distrito

-- inserta una direccion validando existencia de cliente y distrito
CREATE OR ALTER PROCEDURE sp_insertar_direccion
    @id_cliente  INT,
    @id_distrito INT
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        IF @id_cliente  IS NULL RAISERROR('id_cliente no puede ser NULL.',16,1);
        IF @id_distrito IS NULL RAISERROR('id_distrito no puede ser NULL.',16,1);
        -- valida que el cliente y el distrito referenciados existan
        IF NOT EXISTS (SELECT 1 FROM cliente   WHERE id_cliente  = @id_cliente)
            RAISERROR('No existe cliente con id_cliente %d.',16,1,@id_cliente);
        IF NOT EXISTS (SELECT 1 FROM distritos WHERE id_distrito = @id_distrito)
            RAISERROR('No existe distrito con id_distrito %d.',16,1,@id_distrito);
        IF EXISTS (SELECT 1 FROM direccion WHERE id_cliente = @id_cliente AND id_distrito = @id_distrito)
            RAISERROR('La direccion ya existe para este cliente y distrito.',16,1);

        INSERT INTO direccion (id_cliente, id_distrito) VALUES (@id_cliente, @id_distrito);
        SELECT * FROM direccion WHERE id_cliente = @id_cliente AND id_distrito = @id_distrito;
    END TRY
    BEGIN CATCH THROW; END CATCH
END;
GO

-- actualiza la direccion de un cliente cambiando el distrito:
-- elimina el registro viejo e inserta el nuevo para respetar la pk compuesta
CREATE OR ALTER PROCEDURE sp_actualizar_direccion
    @id_cliente      INT,
    @id_distrito_viejo INT,
    @id_distrito_nuevo INT
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM direccion WHERE id_cliente = @id_cliente AND id_distrito = @id_distrito_viejo)
            RAISERROR('No existe la direccion a actualizar para el cliente %d con distrito %d.',16,1,@id_cliente,@id_distrito_viejo);
        IF NOT EXISTS (SELECT 1 FROM distritos WHERE id_distrito = @id_distrito_nuevo)
            RAISERROR('No existe el distrito nuevo %d.',16,1,@id_distrito_nuevo);
        IF EXISTS (SELECT 1 FROM direccion WHERE id_cliente = @id_cliente AND id_distrito = @id_distrito_nuevo)
            RAISERROR('El cliente %d ya tiene registrado el distrito %d.',16,1,@id_cliente,@id_distrito_nuevo);

        -- delete del registro viejo e insert del nuevo dentro de la misma operacion
        DELETE FROM direccion WHERE id_cliente = @id_cliente AND id_distrito = @id_distrito_viejo;
        INSERT INTO direccion (id_cliente, id_distrito) VALUES (@id_cliente, @id_distrito_nuevo);

        SELECT 'Direccion actualizada correctamente.' AS mensaje;
    END TRY
    BEGIN CATCH THROW; END CATCH
END;
GO

-- elimina una direccion por cliente y distrito
CREATE OR ALTER PROCEDURE sp_eliminar_direccion
    @id_cliente  INT,
    @id_distrito INT
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM direccion WHERE id_cliente = @id_cliente AND id_distrito = @id_distrito)
            RAISERROR('No existe la direccion a eliminar para el cliente %d con distrito %d.',16,1,@id_cliente,@id_distrito);

        DELETE FROM direccion WHERE id_cliente = @id_cliente AND id_distrito = @id_distrito;
        SELECT 'Direccion eliminada correctamente.' AS mensaje;
    END TRY
    BEGIN CATCH THROW; END CATCH
END;
GO

-- consulta direcciones; filtra por cliente si se indica
CREATE OR ALTER PROCEDURE sp_consultar_direccion
    @id_cliente INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        IF @id_cliente IS NULL
            SELECT d.id_cliente, d.id_distrito,
                   di.distrito        AS nombre_distrito,
                   c.canton           AS nombre_canton,
                   p.provincia        AS nombre_provincia
            FROM   direccion  d
            JOIN   distritos  di ON di.id_distrito  = d.id_distrito
            JOIN   cantones   c  ON c.id_canton     = di.canton
            JOIN   provincias p  ON p.id_provincia  = c.provincia
            ORDER BY d.id_cliente;
        ELSE
            SELECT d.id_cliente, d.id_distrito,
                   di.distrito        AS nombre_distrito,
                   c.canton           AS nombre_canton,
                   p.provincia        AS nombre_provincia
            FROM   direccion  d
            JOIN   distritos  di ON di.id_distrito  = d.id_distrito
            JOIN   cantones   c  ON c.id_canton     = di.canton
            JOIN   provincias p  ON p.id_provincia  = c.provincia
            WHERE  d.id_cliente = @id_cliente;
    END TRY
    BEGIN CATCH THROW; END CATCH
END;
GO


-- ---- crud: categoria_producto ----

-- inserta una categoria validando que el estado activa exista
CREATE OR ALTER PROCEDURE sp_insertar_categoria_producto
    @nombre         VARCHAR(100),
    @descripcion    VARCHAR(255) = NULL,
    @activa         INT          = 1,
    @comision_venta DECIMAL(5,2) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        IF @nombre IS NULL RAISERROR('nombre no puede ser NULL.',16,1);
        -- valida que el valor de activa exista en activa_inventario
        IF NOT EXISTS (SELECT 1 FROM activa_inventario WHERE id_estado = @activa)
            RAISERROR('El valor activa %d no existe en activa_inventario.',16,1,@activa);

        INSERT INTO categoria_producto (nombre, descripcion, activa, comision_venta)
        VALUES (@nombre, @descripcion, @activa, @comision_venta);

        SELECT * FROM categoria_producto WHERE id_categoria = SCOPE_IDENTITY();
    END TRY
    BEGIN CATCH THROW; END CATCH
END;
GO

-- actualiza nombre, descripcion, activa y comision de una categoria existente
CREATE OR ALTER PROCEDURE sp_actualizar_categoria_producto
    @id_categoria   INT,
    @nombre         VARCHAR(100),
    @descripcion    VARCHAR(255) = NULL,
    @activa         INT,
    @comision_venta DECIMAL(5,2) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM categoria_producto WHERE id_categoria = @id_categoria)
            RAISERROR('No existe la categoria %d.',16,1,@id_categoria);
        IF NOT EXISTS (SELECT 1 FROM activa_inventario WHERE id_estado = @activa)
            RAISERROR('El valor activa %d no existe en activa_inventario.',16,1,@activa);

        UPDATE categoria_producto
        SET nombre = @nombre, descripcion = @descripcion, activa = @activa, comision_venta = @comision_venta
        WHERE id_categoria = @id_categoria;

        SELECT @@ROWCOUNT AS filas_afectadas;
    END TRY
    BEGIN CATCH THROW; END CATCH
END;
GO

-- elimina una categoria por su id
CREATE OR ALTER PROCEDURE sp_eliminar_categoria_producto
    @id_categoria INT
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM categoria_producto WHERE id_categoria = @id_categoria)
            RAISERROR('No existe la categoria %d.',16,1,@id_categoria);

        DELETE FROM categoria_producto WHERE id_categoria = @id_categoria;
        SELECT 'Categoria eliminada correctamente.' AS mensaje;
    END TRY
    BEGIN CATCH THROW; END CATCH
END;
GO

-- consulta una o todas las categorias
CREATE OR ALTER PROCEDURE sp_consultar_categoria_producto
    @id_categoria INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        IF @id_categoria IS NULL
            SELECT * FROM categoria_producto ORDER BY id_categoria;
        ELSE
            SELECT * FROM categoria_producto WHERE id_categoria = @id_categoria;
    END TRY
    BEGIN CATCH THROW; END CATCH
END;
GO

-- ---- crud: tipo_material ----

-- inserta un material validando que la disponibilidad exista
CREATE OR ALTER PROCEDURE sp_insertar_tipo_material
    @nombre_material            VARCHAR(100),
    @proveedor                  VARCHAR(100) = NULL,
    @costo_unitario             TINYINT      = NULL,
    @densidad                   DECIMAL(10,2)= NULL,
    @fecha_ultima_actualizacion DATE         = NULL,
    @descripcion                VARCHAR(255) = NULL,
    @disponibilidad             INT          = 1
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        IF @nombre_material IS NULL RAISERROR('nombre_material no puede ser NULL.',16,1);
        -- valida que la disponibilidad referenciada exista
        IF NOT EXISTS (SELECT 1 FROM disponibilidad_material WHERE id_estado = @disponibilidad)
            RAISERROR('La disponibilidad %d no existe en disponibilidad_material.',16,1,@disponibilidad);

        INSERT INTO tipo_material (nombre_material, proveedor, costo_unitario, densidad,
                                   fecha_ultima_actualizacion, descripcion, disponibilidad)
        VALUES (@nombre_material, @proveedor, @costo_unitario, @densidad,
                @fecha_ultima_actualizacion, @descripcion, @disponibilidad);

        SELECT * FROM tipo_material WHERE id_material = SCOPE_IDENTITY();
    END TRY
    BEGIN CATCH THROW; END CATCH
END;
GO

-- actualiza todos los campos editables de un material existente
CREATE OR ALTER PROCEDURE sp_actualizar_tipo_material
    @id_material                INT,
    @nombre_material            VARCHAR(100),
    @proveedor                  VARCHAR(100) = NULL,
    @costo_unitario             TINYINT      = NULL,
    @densidad                   DECIMAL(10,2)= NULL,
    @fecha_ultima_actualizacion DATE         = NULL,
    @descripcion                VARCHAR(255) = NULL,
    @disponibilidad             INT
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM tipo_material WHERE id_material = @id_material)
            RAISERROR('No existe el material %d.',16,1,@id_material);
        IF NOT EXISTS (SELECT 1 FROM disponibilidad_material WHERE id_estado = @disponibilidad)
            RAISERROR('La disponibilidad %d no existe en disponibilidad_material.',16,1,@disponibilidad);

        UPDATE tipo_material
        SET nombre_material = @nombre_material, proveedor = @proveedor,
            costo_unitario = @costo_unitario, densidad = @densidad,
            fecha_ultima_actualizacion = @fecha_ultima_actualizacion,
            descripcion = @descripcion, disponibilidad = @disponibilidad
        WHERE id_material = @id_material;

        SELECT @@ROWCOUNT AS filas_afectadas;
    END TRY
    BEGIN CATCH THROW; END CATCH
END;
GO

-- elimina un material por su id
CREATE OR ALTER PROCEDURE sp_eliminar_tipo_material
    @id_material INT
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM tipo_material WHERE id_material = @id_material)
            RAISERROR('No existe el material %d.',16,1,@id_material);

        DELETE FROM tipo_material WHERE id_material = @id_material;
        SELECT 'Material eliminado correctamente.' AS mensaje;
    END TRY
    BEGIN CATCH THROW; END CATCH
END;
GO

-- consulta uno o todos los materiales
CREATE OR ALTER PROCEDURE sp_consultar_tipo_material
    @id_material INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        IF @id_material IS NULL
            SELECT * FROM tipo_material ORDER BY id_material;
        ELSE
            SELECT * FROM tipo_material WHERE id_material = @id_material;
    END TRY
    BEGIN CATCH THROW; END CATCH
END;
GO

-- ---- crud: producto ----

-- inserta un producto con validaciones individuales de nulos y de fks referenciadas
CREATE OR ALTER PROCEDURE sp_insertar_producto
    @id_categoria  INT,
    @nombre        VARCHAR(100),
    @descripcion   VARCHAR(100)         = NULL,
    @precio_venta  DECIMAL(10,2),
    @codigo        tipo_codigo_producto,
    @fecha_creacion DATE                = NULL,
    @disponibilidad INT                 = 1,
    @material      INT,
    @tipo          VARCHAR(50)          = NULL,
    @imagen_url    VARCHAR(255)         = NULL
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        -- validaciones de nulos separadas siguiendo el patron del codigo base
        IF @id_categoria  IS NULL RAISERROR('id_categoria no puede ser NULL.',16,1);
        IF @nombre        IS NULL RAISERROR('nombre no puede ser NULL.',16,1);
        IF @precio_venta  IS NULL RAISERROR('precio_venta no puede ser NULL.',16,1);
        IF @codigo        IS NULL RAISERROR('codigo no puede ser NULL.',16,1);
        IF @material      IS NULL RAISERROR('material no puede ser NULL.',16,1);
        -- valida existencia de registros referenciados por fk
        IF NOT EXISTS (SELECT 1 FROM categoria_producto    WHERE id_categoria = @id_categoria)
            RAISERROR('No existe la categoria %d.',16,1,@id_categoria);
        IF NOT EXISTS (SELECT 1 FROM disponible_inventario WHERE id_estado    = @disponibilidad)
            RAISERROR('La disponibilidad %d no existe en disponible_inventario.',16,1,@disponibilidad);
        IF NOT EXISTS (SELECT 1 FROM tipo_material         WHERE id_material  = @material)
            RAISERROR('No existe el material %d.',16,1,@material);
        IF @fecha_creacion IS NULL SET @fecha_creacion = GETDATE();

        INSERT INTO producto (id_categoria, nombre, descripcion, precio_venta, codigo,
                              fecha_creacion, disponibilidad, material, tipo, imagen_url)
        VALUES (@id_categoria, @nombre, @descripcion, @precio_venta, @codigo,
                @fecha_creacion, @disponibilidad, @material, @tipo, @imagen_url);

        SELECT * FROM producto WHERE id_producto = SCOPE_IDENTITY();
    END TRY
    BEGIN CATCH THROW; END CATCH
END;
GO

-- actualiza los campos editables de un producto existente
CREATE OR ALTER PROCEDURE sp_actualizar_producto
    @id_producto    INT,
    @id_categoria   INT,
    @nombre         VARCHAR(100),
    @descripcion    VARCHAR(100)         = NULL,
    @precio_venta   DECIMAL(10,2),
    @codigo         tipo_codigo_producto,
    @disponibilidad INT,
    @material       INT,
    @tipo           VARCHAR(50)          = NULL,
    @imagen_url     VARCHAR(255)         = NULL
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM producto              WHERE id_producto  = @id_producto)
            RAISERROR('No existe el producto %d.',16,1,@id_producto);
        IF NOT EXISTS (SELECT 1 FROM categoria_producto    WHERE id_categoria = @id_categoria)
            RAISERROR('No existe la categoria %d.',16,1,@id_categoria);
        IF NOT EXISTS (SELECT 1 FROM disponible_inventario WHERE id_estado    = @disponibilidad)
            RAISERROR('La disponibilidad %d no existe en disponible_inventario.',16,1,@disponibilidad);
        IF NOT EXISTS (SELECT 1 FROM tipo_material         WHERE id_material  = @material)
            RAISERROR('No existe el material %d.',16,1,@material);

        UPDATE producto
        SET id_categoria = @id_categoria, nombre = @nombre, descripcion = @descripcion,
            precio_venta = @precio_venta, codigo = @codigo, disponibilidad = @disponibilidad,
            material = @material, tipo = @tipo, imagen_url = @imagen_url
        WHERE id_producto = @id_producto;

        SELECT @@ROWCOUNT AS filas_afectadas;
    END TRY
    BEGIN CATCH THROW; END CATCH
END;
GO

-- elimina un producto por su id
CREATE OR ALTER PROCEDURE sp_eliminar_producto
    @id_producto INT
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM producto WHERE id_producto = @id_producto)
            RAISERROR('No existe el producto %d.',16,1,@id_producto);

        DELETE FROM producto WHERE id_producto = @id_producto;
        SELECT 'Producto eliminado correctamente.' AS mensaje;
    END TRY
    BEGIN CATCH THROW; END CATCH
END;
GO

-- consulta uno o todos los productos
CREATE OR ALTER PROCEDURE sp_consultar_producto
    @id_producto INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        IF @id_producto IS NULL
            SELECT * FROM producto ORDER BY id_producto;
        ELSE
            SELECT * FROM producto WHERE id_producto = @id_producto;
    END TRY
    BEGIN CATCH THROW; END CATCH
END;
GO

-- ---- crud: inventario ----

-- inserta el registro de inventario de un producto; un producto tiene un solo inventario (uq)
CREATE OR ALTER PROCEDURE sp_insertar_inventario
    @id_producto         INT,
    @unidades_vendidas   INT = 0,
    @cantidad_disponible INT,
    @cantidad_minima     INT,
    @cantidad_maxima     INT,
    @estado              INT = 1
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        IF @id_producto IS NULL RAISERROR('id_producto no puede ser NULL.',16,1);
        IF NOT EXISTS (SELECT 1 FROM producto         WHERE id_producto = @id_producto)
            RAISERROR('No existe el producto %d.',16,1,@id_producto);
        IF NOT EXISTS (SELECT 1 FROM estado_inventario WHERE id_estado  = @estado)
            RAISERROR('El estado %d no existe en estado_inventario.',16,1,@estado);
        -- respeta la restriccion uq_inventario_producto: un inventario por producto
        IF EXISTS (SELECT 1 FROM inventario WHERE id_producto = @id_producto)
            RAISERROR('Ya existe inventario para el producto %d.',16,1,@id_producto);

        INSERT INTO inventario (id_producto, unidades_vendidas, cantidad_disponible,
                                cantidad_minima, cantidad_maxima, estado)
        VALUES (@id_producto, @unidades_vendidas, @cantidad_disponible,
                @cantidad_minima, @cantidad_maxima, @estado);

        SELECT * FROM inventario WHERE id_inventario = SCOPE_IDENTITY();
    END TRY
    BEGIN CATCH THROW; END CATCH
END;
GO

-- actualiza cantidades y estado de un inventario existente
CREATE OR ALTER PROCEDURE sp_actualizar_inventario
    @id_inventario       INT,
    @unidades_vendidas   INT,
    @cantidad_disponible INT,
    @cantidad_minima     INT,
    @cantidad_maxima     INT,
    @estado              INT
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM inventario       WHERE id_inventario = @id_inventario)
            RAISERROR('No existe el inventario %d.',16,1,@id_inventario);
        IF NOT EXISTS (SELECT 1 FROM estado_inventario WHERE id_estado    = @estado)
            RAISERROR('El estado %d no existe en estado_inventario.',16,1,@estado);

        UPDATE inventario
        SET unidades_vendidas = @unidades_vendidas, cantidad_disponible = @cantidad_disponible,
            cantidad_minima = @cantidad_minima, cantidad_maxima = @cantidad_maxima, estado = @estado
        WHERE id_inventario = @id_inventario;

        SELECT @@ROWCOUNT AS filas_afectadas;
    END TRY
    BEGIN CATCH THROW; END CATCH
END;
GO

-- elimina un registro de inventario por su id
CREATE OR ALTER PROCEDURE sp_eliminar_inventario
    @id_inventario INT
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM inventario WHERE id_inventario = @id_inventario)
            RAISERROR('No existe el inventario %d.',16,1,@id_inventario);

        DELETE FROM inventario WHERE id_inventario = @id_inventario;
        SELECT 'Inventario eliminado correctamente.' AS mensaje;
    END TRY
    BEGIN CATCH THROW; END CATCH
END;
GO

-- consulta uno o todos los registros de inventario
CREATE OR ALTER PROCEDURE sp_consultar_inventario
    @id_inventario INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        IF @id_inventario IS NULL
            SELECT * FROM inventario ORDER BY id_inventario;
        ELSE
            SELECT * FROM inventario WHERE id_inventario = @id_inventario;
    END TRY
    BEGIN CATCH THROW; END CATCH
END;
GO

-- ---- crud: compra ----

-- inserta una compra validando cliente y estado de pago
CREATE OR ALTER PROCEDURE sp_insertar_compra
    @id_cliente     INT,
    @numero_factura VARCHAR(50)   = NULL,
    @fecha_compra   DATE          = NULL,
    @monto_total    tipo_monto    = 0,
    @estado_pago    TINYINT       = 2,
    @flujo_ingresos DECIMAL(10,2) = NULL,
    @comentarios    VARCHAR(255)  = NULL
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        IF @id_cliente IS NULL RAISERROR('id_cliente no puede ser NULL.',16,1);
        -- valida existencia de cliente y de estado de pago
        IF NOT EXISTS (SELECT 1 FROM cliente     WHERE id_cliente = @id_cliente)
            RAISERROR('No existe cliente con id_cliente %d.',16,1,@id_cliente);
        IF NOT EXISTS (SELECT 1 FROM estado_pago WHERE id_estado  = @estado_pago)
            RAISERROR('El estado_pago %d no existe en estado_pago.',16,1,@estado_pago);
        IF @fecha_compra IS NULL SET @fecha_compra = GETDATE();

        INSERT INTO compra (id_cliente, numero_factura, fecha_compra, monto_total,
                            estado_pago, flujo_ingresos, comentarios)
        VALUES (@id_cliente, @numero_factura, @fecha_compra, @monto_total,
                @estado_pago, @flujo_ingresos, @comentarios);

        SELECT * FROM compra WHERE id_compra = SCOPE_IDENTITY();
    END TRY
    BEGIN CATCH THROW; END CATCH
END;
GO

-- actualiza estado, monto, flujo y comentarios de una compra existente
CREATE OR ALTER PROCEDURE sp_actualizar_compra
    @id_compra      INT,
    @estado_pago    TINYINT,
    @monto_total    tipo_monto,
    @flujo_ingresos DECIMAL(10,2) = NULL,
    @comentarios    VARCHAR(255)  = NULL
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM compra      WHERE id_compra = @id_compra)
            RAISERROR('No existe la compra %d.',16,1,@id_compra);
        IF NOT EXISTS (SELECT 1 FROM estado_pago WHERE id_estado = @estado_pago)
            RAISERROR('El estado_pago %d no existe en estado_pago.',16,1,@estado_pago);

        UPDATE compra
        SET estado_pago = @estado_pago, monto_total = @monto_total,
            flujo_ingresos = @flujo_ingresos, comentarios = @comentarios
        WHERE id_compra = @id_compra;

        SELECT @@ROWCOUNT AS filas_afectadas;
    END TRY
    BEGIN CATCH THROW; END CATCH
END;
GO

-- elimina una compra por su id (el cascade elimina detalle_compra e ingreso)
CREATE OR ALTER PROCEDURE sp_eliminar_compra
    @id_compra INT
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM compra WHERE id_compra = @id_compra)
            RAISERROR('No existe la compra %d.',16,1,@id_compra);

        DELETE FROM compra WHERE id_compra = @id_compra;
        SELECT 'Compra eliminada correctamente.' AS mensaje;
    END TRY
    BEGIN CATCH THROW; END CATCH
END;
GO

-- consulta una o todas las compras
CREATE OR ALTER PROCEDURE sp_consultar_compra
    @id_compra INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        IF @id_compra IS NULL
            SELECT * FROM compra ORDER BY id_compra;
        ELSE
            SELECT * FROM compra WHERE id_compra = @id_compra;
    END TRY
    BEGIN CATCH THROW; END CATCH
END;
GO

-- ---- crud: detalle_compra ----
-- pk compuesta (id_compra, id_producto)

-- inserta un detalle validando compra, producto y duplicado en pk compuesta
CREATE OR ALTER PROCEDURE sp_insertar_detalle_compra
    @id_compra       INT,
    @id_producto     INT,
    @cantidad        INT,
    @precio_unitario DECIMAL(10,2)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        IF @id_compra       IS NULL RAISERROR('id_compra no puede ser NULL.',16,1);
        IF @id_producto     IS NULL RAISERROR('id_producto no puede ser NULL.',16,1);
        IF @cantidad        IS NULL RAISERROR('cantidad no puede ser NULL.',16,1);
        IF @precio_unitario IS NULL RAISERROR('precio_unitario no puede ser NULL.',16,1);
        -- valida existencia de la compra y del producto referenciados
        IF NOT EXISTS (SELECT 1 FROM compra   WHERE id_compra   = @id_compra)
            RAISERROR('No existe la compra %d.',16,1,@id_compra);
        IF NOT EXISTS (SELECT 1 FROM producto WHERE id_producto = @id_producto)
            RAISERROR('No existe el producto %d.',16,1,@id_producto);
        -- evita duplicado en la pk compuesta
        IF EXISTS (SELECT 1 FROM detalle_compra WHERE id_compra = @id_compra AND id_producto = @id_producto)
            RAISERROR('El producto %d ya existe en la compra %d.',16,1,@id_producto,@id_compra);

        INSERT INTO detalle_compra (id_compra, id_producto, cantidad, precio_unitario)
        VALUES (@id_compra, @id_producto, @cantidad, @precio_unitario);

        SELECT * FROM detalle_compra WHERE id_compra = @id_compra AND id_producto = @id_producto;
    END TRY
    BEGIN CATCH THROW; END CATCH
END;
GO

-- actualiza cantidad y precio de un detalle existente
CREATE OR ALTER PROCEDURE sp_actualizar_detalle_compra
    @id_compra       INT,
    @id_producto     INT,
    @cantidad        INT,
    @precio_unitario DECIMAL(10,2)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM detalle_compra
                       WHERE id_compra = @id_compra AND id_producto = @id_producto)
            RAISERROR('No existe detalle de la compra %d con producto %d.',16,1,@id_compra,@id_producto);

        UPDATE detalle_compra
        SET cantidad = @cantidad, precio_unitario = @precio_unitario
        WHERE id_compra = @id_compra AND id_producto = @id_producto;

        SELECT @@ROWCOUNT AS filas_afectadas;
    END TRY
    BEGIN CATCH THROW; END CATCH
END;
GO

-- elimina un detalle de compra por su pk compuesta
CREATE OR ALTER PROCEDURE sp_eliminar_detalle_compra
    @id_compra   INT,
    @id_producto INT
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM detalle_compra
                       WHERE id_compra = @id_compra AND id_producto = @id_producto)
            RAISERROR('No existe detalle de la compra %d con producto %d.',16,1,@id_compra,@id_producto);

        DELETE FROM detalle_compra WHERE id_compra = @id_compra AND id_producto = @id_producto;
        SELECT 'Detalle eliminado correctamente.' AS mensaje;
    END TRY
    BEGIN CATCH THROW; END CATCH
END;
GO

-- consulta detalles de una compra o todos los detalles
CREATE OR ALTER PROCEDURE sp_consultar_detalle_compra
    @id_compra INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        IF @id_compra IS NULL
            SELECT * FROM detalle_compra ORDER BY id_compra;
        ELSE
            SELECT * FROM detalle_compra WHERE id_compra = @id_compra;
    END TRY
    BEGIN CATCH THROW; END CATCH
END;
GO

-- ---- crud: pago ----

-- inserta un pago validando cliente, compra y estado de pago
CREATE OR ALTER PROCEDURE sp_insertar_pago
    @id_cliente         INT,
    @id_compra          INT,
    @numero_referencia  VARCHAR(50)  = NULL,
    @estado_pago        TINYINT,
    @numero_comprobante VARCHAR(100) = NULL,
    @monto_pagado       DECIMAL(10,2),
    @fecha_pago         DATE         = NULL,
    @metodo_pago        VARCHAR(50),
    @notas              VARCHAR(255) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        IF @id_cliente   IS NULL RAISERROR('id_cliente no puede ser NULL.',16,1);
        IF @id_compra    IS NULL RAISERROR('id_compra no puede ser NULL.',16,1);
        IF @monto_pagado IS NULL RAISERROR('monto_pagado no puede ser NULL.',16,1);
        IF @metodo_pago  IS NULL RAISERROR('metodo_pago no puede ser NULL.',16,1);
        IF NOT EXISTS (SELECT 1 FROM cliente     WHERE id_cliente = @id_cliente)
            RAISERROR('No existe cliente con id_cliente %d.',16,1,@id_cliente);
        IF NOT EXISTS (SELECT 1 FROM compra      WHERE id_compra  = @id_compra)
            RAISERROR('No existe la compra %d.',16,1,@id_compra);
        IF NOT EXISTS (SELECT 1 FROM estado_pago WHERE id_estado  = @estado_pago)
            RAISERROR('El estado_pago %d no existe en estado_pago.',16,1,@estado_pago);
        IF @fecha_pago IS NULL SET @fecha_pago = GETDATE();

        INSERT INTO pago (id_cliente, id_compra, numero_referencia, estado_pago,
                          numero_comprobante, monto_pagado, fecha_pago, metodo_pago, notas)
        VALUES (@id_cliente, @id_compra, @numero_referencia, @estado_pago,
                @numero_comprobante, @monto_pagado, @fecha_pago, @metodo_pago, @notas);

        SELECT * FROM pago WHERE id_pago = SCOPE_IDENTITY();
    END TRY
    BEGIN CATCH THROW; END CATCH
END;
GO

-- actualiza estado, monto y notas de un pago existente
CREATE OR ALTER PROCEDURE sp_actualizar_pago
    @id_pago     INT,
    @estado_pago TINYINT,
    @monto_pagado DECIMAL(10,2),
    @notas       VARCHAR(255) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM pago        WHERE id_pago  = @id_pago)
            RAISERROR('No existe el pago %d.',16,1,@id_pago);
        IF NOT EXISTS (SELECT 1 FROM estado_pago WHERE id_estado = @estado_pago)
            RAISERROR('El estado_pago %d no existe en estado_pago.',16,1,@estado_pago);

        UPDATE pago
        SET estado_pago = @estado_pago, monto_pagado = @monto_pagado, notas = @notas
        WHERE id_pago = @id_pago;

        SELECT @@ROWCOUNT AS filas_afectadas;
    END TRY
    BEGIN CATCH THROW; END CATCH
END;
GO

-- elimina un pago por su id
CREATE OR ALTER PROCEDURE sp_eliminar_pago
    @id_pago INT
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM pago WHERE id_pago = @id_pago)
            RAISERROR('No existe el pago %d.',16,1,@id_pago);

        DELETE FROM pago WHERE id_pago = @id_pago;
        SELECT 'Pago eliminado correctamente.' AS mensaje;
    END TRY
    BEGIN CATCH THROW; END CATCH
END;
GO

-- consulta uno o todos los pagos
CREATE OR ALTER PROCEDURE sp_consultar_pago
    @id_pago INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        IF @id_pago IS NULL
            SELECT * FROM pago ORDER BY id_pago;
        ELSE
            SELECT * FROM pago WHERE id_pago = @id_pago;
    END TRY
    BEGIN CATCH THROW; END CATCH
END;
GO

-- ---- crud: ingreso ----

-- inserta un ingreso validando compra, cuenta y estado
CREATE OR ALTER PROCEDURE sp_insertar_ingreso
    @id_compra       INT,
    @id_cuenta       TINYINT,
    @metodo_pago     VARCHAR(50),
    @monto_ingresado DECIMAL(10,2),
    @referencia_banco VARCHAR(100) = NULL,
    @estado          TINYINT       = 2,
    @flujo_ingresado DECIMAL(10,2) = NULL,
    @fecha_ingreso   DATE          = NULL
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        IF @id_compra       IS NULL RAISERROR('id_compra no puede ser NULL.',16,1);
        IF @id_cuenta       IS NULL RAISERROR('id_cuenta no puede ser NULL.',16,1);
        IF @metodo_pago     IS NULL RAISERROR('metodo_pago no puede ser NULL.',16,1);
        IF @monto_ingresado IS NULL RAISERROR('monto_ingresado no puede ser NULL.',16,1);
        IF NOT EXISTS (SELECT 1 FROM compra          WHERE id_compra = @id_compra)
            RAISERROR('No existe la compra %d.',16,1,@id_compra);
        IF NOT EXISTS (SELECT 1 FROM cuenta_bancaria WHERE id_cuenta = @id_cuenta)
            RAISERROR('No existe la cuenta bancaria %d.',16,1,@id_cuenta);
        IF NOT EXISTS (SELECT 1 FROM estado_pago     WHERE id_estado = @estado)
            RAISERROR('El estado %d no existe en estado_pago.',16,1,@estado);
        IF @fecha_ingreso IS NULL SET @fecha_ingreso = GETDATE();

        INSERT INTO ingreso (id_compra, id_cuenta, metodo_pago, monto_ingresado,
                             referencia_banco, estado, flujo_ingresado, fecha_ingreso)
        VALUES (@id_compra, @id_cuenta, @metodo_pago, @monto_ingresado,
                @referencia_banco, @estado, @flujo_ingresado, @fecha_ingreso);

        SELECT * FROM ingreso WHERE id_ingreso = SCOPE_IDENTITY();
    END TRY
    BEGIN CATCH THROW; END CATCH
END;
GO

-- actualiza estado y monto de un ingreso existente
CREATE OR ALTER PROCEDURE sp_actualizar_ingreso
    @id_ingreso      INT,
    @estado          TINYINT,
    @monto_ingresado DECIMAL(10,2)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM ingreso     WHERE id_ingreso = @id_ingreso)
            RAISERROR('No existe el ingreso %d.',16,1,@id_ingreso);
        IF NOT EXISTS (SELECT 1 FROM estado_pago WHERE id_estado  = @estado)
            RAISERROR('El estado %d no existe en estado_pago.',16,1,@estado);

        UPDATE ingreso
        SET estado = @estado, monto_ingresado = @monto_ingresado
        WHERE id_ingreso = @id_ingreso;

        SELECT @@ROWCOUNT AS filas_afectadas;
    END TRY
    BEGIN CATCH THROW; END CATCH
END;
GO

-- elimina un ingreso por su id
CREATE OR ALTER PROCEDURE sp_eliminar_ingreso
    @id_ingreso INT
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM ingreso WHERE id_ingreso = @id_ingreso)
            RAISERROR('No existe el ingreso %d.',16,1,@id_ingreso);

        DELETE FROM ingreso WHERE id_ingreso = @id_ingreso;
        SELECT 'Ingreso eliminado correctamente.' AS mensaje;
    END TRY
    BEGIN CATCH THROW; END CATCH
END;
GO

-- consulta uno o todos los ingresos
CREATE OR ALTER PROCEDURE sp_consultar_ingreso
    @id_ingreso INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        IF @id_ingreso IS NULL
            SELECT * FROM ingreso ORDER BY id_ingreso;
        ELSE
            SELECT * FROM ingreso WHERE id_ingreso = @id_ingreso;
    END TRY
    BEGIN CATCH THROW; END CATCH
END;
GO

-- ---- crud: cuenta_bancaria ----

-- inserta una cuenta bancaria validando duplicado y estado
CREATE OR ALTER PROCEDURE sp_insertar_cuenta_bancaria
    @id_cuenta     TINYINT,
    @tipo_cuenta   VARCHAR(50),
    @titular       VARCHAR(100),
    @saldo_actual  DECIMAL(10,2) = 0,
    @iban          VARCHAR(50)   = NULL,
    @contacto_banco VARCHAR(30)  = NULL,
    @estado        INT           = 1,
    @fecha_apertura DATE         = NULL,
    @numero_cuenta VARCHAR(50)   = NULL,
    @nombre_banco  VARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        IF @id_cuenta    IS NULL RAISERROR('id_cuenta no puede ser NULL.',16,1);
        IF @tipo_cuenta  IS NULL RAISERROR('tipo_cuenta no puede ser NULL.',16,1);
        IF @titular      IS NULL RAISERROR('titular no puede ser NULL.',16,1);
        IF @nombre_banco IS NULL RAISERROR('nombre_banco no puede ser NULL.',16,1);
        IF NOT EXISTS (SELECT 1 FROM estado_cuenta WHERE id_estado = @estado)
            RAISERROR('El estado %d no existe en estado_cuenta.',16,1,@estado);
        IF EXISTS (SELECT 1 FROM cuenta_bancaria WHERE id_cuenta = @id_cuenta)
            RAISERROR('La cuenta con id_cuenta %d ya existe.',16,1,@id_cuenta);

        INSERT INTO cuenta_bancaria (id_cuenta, tipo_cuenta, titular, saldo_actual, iban,
                                     contacto_banco, estado, fecha_apertura, numero_cuenta, nombre_banco)
        VALUES (@id_cuenta, @tipo_cuenta, @titular, @saldo_actual, @iban,
                @contacto_banco, @estado, @fecha_apertura, @numero_cuenta, @nombre_banco);

        SELECT * FROM cuenta_bancaria WHERE id_cuenta = @id_cuenta;
    END TRY
    BEGIN CATCH THROW; END CATCH
END;
GO

-- actualiza saldo y estado de una cuenta existente
CREATE OR ALTER PROCEDURE sp_actualizar_cuenta_bancaria
    @id_cuenta    TINYINT,
    @saldo_actual DECIMAL(10,2),
    @estado       INT
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM cuenta_bancaria WHERE id_cuenta = @id_cuenta)
            RAISERROR('No existe la cuenta bancaria %d.',16,1,@id_cuenta);
        IF NOT EXISTS (SELECT 1 FROM estado_cuenta   WHERE id_estado = @estado)
            RAISERROR('El estado %d no existe en estado_cuenta.',16,1,@estado);

        UPDATE cuenta_bancaria
        SET saldo_actual = @saldo_actual, estado = @estado
        WHERE id_cuenta = @id_cuenta;

        SELECT @@ROWCOUNT AS filas_afectadas;
    END TRY
    BEGIN CATCH THROW; END CATCH
END;
GO

-- elimina una cuenta bancaria por su id
CREATE OR ALTER PROCEDURE sp_eliminar_cuenta_bancaria
    @id_cuenta TINYINT
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM cuenta_bancaria WHERE id_cuenta = @id_cuenta)
            RAISERROR('No existe la cuenta bancaria %d.',16,1,@id_cuenta);

        DELETE FROM cuenta_bancaria WHERE id_cuenta = @id_cuenta;
        SELECT 'Cuenta bancaria eliminada correctamente.' AS mensaje;
    END TRY
    BEGIN CATCH THROW; END CATCH
END;
GO

-- consulta una o todas las cuentas bancarias
CREATE OR ALTER PROCEDURE sp_consultar_cuenta_bancaria
    @id_cuenta TINYINT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        IF @id_cuenta IS NULL
            SELECT * FROM cuenta_bancaria ORDER BY id_cuenta;
        ELSE
            SELECT * FROM cuenta_bancaria WHERE id_cuenta = @id_cuenta;
    END TRY
    BEGIN CATCH THROW; END CATCH
END;
GO

-- ---- crud: gastos ----

-- inserta un gasto validando existencia de la cuenta referenciada
CREATE OR ALTER PROCEDURE sp_insertar_gastos
    @id_cuenta       TINYINT,
    @responsable     VARCHAR(100) = NULL,
    @fecha_registro  DATE         = NULL,
    @fecha_gasto     DATE,
    @descripcion     VARCHAR(255) = NULL,
    @categoria       VARCHAR(100) = NULL,
    @monto           tipo_monto,
    @comprobante     VARCHAR(100) = NULL,
    @notas           VARCHAR(255) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        IF @id_cuenta   IS NULL RAISERROR('id_cuenta no puede ser NULL.',16,1);
        IF @fecha_gasto IS NULL RAISERROR('fecha_gasto no puede ser NULL.',16,1);
        IF @monto       IS NULL RAISERROR('monto no puede ser NULL.',16,1);
        IF NOT EXISTS (SELECT 1 FROM cuenta_bancaria WHERE id_cuenta = @id_cuenta)
            RAISERROR('No existe la cuenta bancaria %d.',16,1,@id_cuenta);
        IF @fecha_registro IS NULL SET @fecha_registro = GETDATE();

        INSERT INTO gastos (id_cuenta, responsable, fecha_registro, fecha_gasto,
                            descripcion, categoria, monto, comprobante, notas)
        VALUES (@id_cuenta, @responsable, @fecha_registro, @fecha_gasto,
                @descripcion, @categoria, @monto, @comprobante, @notas);

        SELECT * FROM gastos WHERE id_gastos = SCOPE_IDENTITY();
    END TRY
    BEGIN CATCH THROW; END CATCH
END;
GO

-- actualiza monto, descripcion y categoria de un gasto existente
CREATE OR ALTER PROCEDURE sp_actualizar_gastos
    @id_gastos   INT,
    @monto       tipo_monto,
    @descripcion VARCHAR(255) = NULL,
    @categoria   VARCHAR(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM gastos WHERE id_gastos = @id_gastos)
            RAISERROR('No existe el gasto %d.',16,1,@id_gastos);

        UPDATE gastos
        SET monto = @monto, descripcion = @descripcion, categoria = @categoria
        WHERE id_gastos = @id_gastos;

        SELECT @@ROWCOUNT AS filas_afectadas;
    END TRY
    BEGIN CATCH THROW; END CATCH
END;
GO

-- elimina un gasto por su id
CREATE OR ALTER PROCEDURE sp_eliminar_gastos
    @id_gastos INT
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM gastos WHERE id_gastos = @id_gastos)
            RAISERROR('No existe el gasto %d.',16,1,@id_gastos);

        DELETE FROM gastos WHERE id_gastos = @id_gastos;
        SELECT 'Gasto eliminado correctamente.' AS mensaje;
    END TRY
    BEGIN CATCH THROW; END CATCH
END;
GO

-- consulta uno o todos los gastos
CREATE OR ALTER PROCEDURE sp_consultar_gastos
    @id_gastos INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        IF @id_gastos IS NULL
            SELECT * FROM gastos ORDER BY id_gastos;
        ELSE
            SELECT * FROM gastos WHERE id_gastos = @id_gastos;
    END TRY
    BEGIN CATCH THROW; END CATCH
END;
GO





-- =============================================================================
-- Sección 9: Procedimientos con Transacciones
-- Cada procedimiento opera con BEGIN/COMMIT/ROLLBACK para garantizar atomicidad.
-- Las validaciones de precondición se hacen ANTES del BEGIN TRANSACTION para
-- no mantener bloqueos abiertos mientras se chequean condiciones.
-- =============================================================================

-- ============================================================
-- TRANSACCIÓN 1: sp_registrar_venta_completa
-- Registra una venta de principio a fin en una sola operación atómica:
--   1. Crea la cabecera en compra
--   2. Inserta cada línea en detalle_compra
--   3. Descuenta unidades en inventario y suma unidades_vendidas
--   4. Marca el producto como 'agotado' si la cantidad cae a 0
--   5. Recalcula y actualiza monto_total en compra
-- Si cualquier paso falla, se revierte todo.
-- ============================================================
CREATE OR ALTER PROCEDURE sp_registrar_venta_completa
    @id_cliente     INT,
    @numero_factura VARCHAR(50),
    @id_cuenta      TINYINT,          -- cuenta bancaria que recibe el pago
    @metodo_pago    VARCHAR(50),
    @comentarios    VARCHAR(255) = NULL,
    -- productos: se reciben como xml con el esquema:
    -- <items><item id_producto="1" cantidad="2"/><item .../></items>
    @items          XML
AS
BEGIN
    SET NOCOUNT ON;

    -- variables de trabajo
    DECLARE @id_compra      INT;
    DECLARE @monto_total    DECIMAL(10,2) = 0;
    DECLARE @id_producto    INT;
    DECLARE @cantidad       INT;
    DECLARE @precio_unitario DECIMAL(10,2);
    DECLARE @stock_actual   INT;
    DECLARE @nuevo_stock    INT;

    BEGIN TRY
        -- validaciones previas fuera de la transacción para no bloquear innecesariamente
        IF @id_cliente IS NULL
            RAISERROR('id_cliente no puede ser NULL.',16,1);
        IF NOT EXISTS (SELECT 1 FROM cliente WHERE id_cliente = @id_cliente)
            RAISERROR('No existe el cliente %d.',16,1,@id_cliente);
        IF NOT EXISTS (SELECT 1 FROM cuenta_bancaria WHERE id_cuenta = @id_cuenta)
            RAISERROR('No existe la cuenta bancaria %d.',16,1,@id_cuenta);
        IF @items IS NULL
            RAISERROR('La lista de productos no puede ser NULL.',16,1);

        -- verifica que cada producto exista y tenga stock suficiente antes de iniciar
        IF EXISTS (
            SELECT 1
            FROM   @items.nodes('/items/item') AS T(item)
            CROSS  APPLY (
                SELECT T.item.value('@id_producto','INT') AS id_p,
                       T.item.value('@cantidad','INT')    AS qty
            ) x
            WHERE NOT EXISTS (
                SELECT 1
                FROM   inventario i
                JOIN   producto   p ON p.id_producto = i.id_producto
                WHERE  i.id_producto         = x.id_p
                  AND  i.cantidad_disponible >= x.qty
                  AND  p.disponibilidad      = 1        -- solo productos disponibles
            )
        )
            RAISERROR('Uno o mas productos no tienen stock suficiente o no estan disponibles.',16,1);

        BEGIN TRANSACTION;

            -- paso 1: insertar cabecera de compra con estado pendiente (2)
            INSERT INTO compra (id_cliente, numero_factura, fecha_compra, monto_total, estado_pago, comentarios)
            VALUES (@id_cliente, @numero_factura, GETDATE(), 0, 2, @comentarios);

            SET @id_compra = SCOPE_IDENTITY();

            -- paso 2 y 3: recorrer los productos del xml
            DECLARE cur_items CURSOR LOCAL FAST_FORWARD FOR
                SELECT T.item.value('@id_producto','INT'),
                       T.item.value('@cantidad','INT')
                FROM   @items.nodes('/items/item') AS T(item);

            OPEN cur_items;
            FETCH NEXT FROM cur_items INTO @id_producto, @cantidad;

            WHILE @@FETCH_STATUS = 0
            BEGIN
                -- obtiene precio actual del catálogo
                SELECT @precio_unitario = precio_venta
                FROM   producto
                WHERE  id_producto = @id_producto;

                -- inserta línea de detalle
                INSERT INTO detalle_compra (id_compra, id_producto, cantidad, precio_unitario)
                VALUES (@id_compra, @id_producto, @cantidad, @precio_unitario);

                -- acumula el total
                SET @monto_total = @monto_total + (@cantidad * @precio_unitario);

                -- descuenta stock y suma unidades vendidas
                SELECT @stock_actual = cantidad_disponible
                FROM   inventario
                WHERE  id_producto = @id_producto;

                SET @nuevo_stock = @stock_actual - @cantidad;

                UPDATE inventario
                SET    cantidad_disponible = @nuevo_stock,
                       unidades_vendidas   = unidades_vendidas + @cantidad
                WHERE  id_producto = @id_producto;

                -- si el stock llega a 0 marca el producto como agotado (id 2)
                IF @nuevo_stock = 0
                    UPDATE producto
                    SET    disponibilidad = 2
                    WHERE  id_producto = @id_producto;

                FETCH NEXT FROM cur_items INTO @id_producto, @cantidad;
            END;

            CLOSE cur_items;
            DEALLOCATE cur_items;

            -- paso 4: actualiza el monto total calculado en la cabecera
            UPDATE compra
            SET    monto_total = @monto_total
            WHERE  id_compra = @id_compra;

            -- paso 5: registra el ingreso en la cuenta bancaria indicada
            INSERT INTO ingreso (id_compra, id_cuenta, metodo_pago, monto_ingresado,
                                 estado, flujo_ingresado, fecha_ingreso)
            VALUES (@id_compra, @id_cuenta, @metodo_pago, @monto_total,
                    2, @monto_total, GETDATE());  -- estado 2 = pendiente

        COMMIT TRANSACTION;

        -- retorna el resumen de la venta registrada
        SELECT c.id_compra, c.numero_factura, c.fecha_compra,
               c.monto_total, ep.descripcion AS estado_pago
        FROM   compra      c
        JOIN   estado_pago ep ON ep.id_estado = c.estado_pago
        WHERE  c.id_compra = @id_compra;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO


-- ============================================================
-- TRANSACCIÓN 2: sp_confirmar_pago
-- Confirma el pago de una compra pendiente en una sola operación:
--   1. Valida que la compra exista y esté en estado pendiente
--   2. Inserta el registro en pago
--   3. Actualiza estado_pago en compra  → 'aplicado' (1)
--   4. Actualiza estado en ingreso      → 'aplicado' (1) y guarda referencia
--   5. Suma el monto al saldo de la cuenta bancaria
-- Si cualquier paso falla, se revierte todo.
-- ============================================================
CREATE OR ALTER PROCEDURE sp_confirmar_pago
    @id_compra          INT,
    @id_cliente         INT,
    @id_cuenta          TINYINT,
    @monto_pagado       DECIMAL(10,2),
    @metodo_pago        VARCHAR(50),
    @numero_referencia  VARCHAR(50)  = NULL,
    @numero_comprobante VARCHAR(100) = NULL,
    @notas              VARCHAR(255) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @monto_esperado DECIMAL(10,2);
    DECLARE @id_ingreso     INT;

    BEGIN TRY
        -- validaciones previas
        IF NOT EXISTS (SELECT 1 FROM compra  WHERE id_compra  = @id_compra)
            RAISERROR('No existe la compra %d.',16,1,@id_compra);
        IF NOT EXISTS (SELECT 1 FROM cliente WHERE id_cliente = @id_cliente)
            RAISERROR('No existe el cliente %d.',16,1,@id_cliente);
        IF NOT EXISTS (SELECT 1 FROM cuenta_bancaria WHERE id_cuenta = @id_cuenta)
            RAISERROR('No existe la cuenta bancaria %d.',16,1,@id_cuenta);

        -- la compra debe estar en estado pendiente (2)
        IF NOT EXISTS (SELECT 1 FROM compra WHERE id_compra = @id_compra AND estado_pago = 2)
            RAISERROR('La compra %d no está en estado pendiente.',16,1,@id_compra);

        
        IF NOT EXISTS (SELECT 1 FROM ingreso WHERE  id_compra = @id_compra AND  id_cuenta = @id_cuenta)
            RAISERROR('La cuenta %d no corresponde al ingreso de la compra %d.',16,1,@id_cuenta,@id_compra);

        -- el monto pagado debe coincidir con el total de la compra
        SELECT @monto_esperado = monto_total FROM compra WHERE id_compra = @id_compra;
        IF @monto_pagado <> @monto_esperado
            DECLARE @var_temp VARCHAR(20) = CAST(@monto_pagado AS VARCHAR(20));
            DECLARE @var_temp2 VARCHAR(20) = CAST(@monto_esperado AS VARCHAR(20));
            RAISERROR('El monto pagado (%.2f) no coincide con el total de la compra (%.2f).',
                      16,1,@var_temp,@var_temp2);

        BEGIN TRANSACTION;

            -- paso 1: registra el pago
            INSERT INTO pago (id_cliente, id_compra, numero_referencia, estado_pago,
                              numero_comprobante, monto_pagado, fecha_pago, metodo_pago, notas)
            VALUES (@id_cliente, @id_compra, @numero_referencia, 1,
                    @numero_comprobante, @monto_pagado, GETDATE(), @metodo_pago, @notas);

            -- paso 2: marca la compra como aplicada (1)
            UPDATE compra
            SET    estado_pago    = 1,
                   flujo_ingresos = @monto_pagado
            WHERE  id_compra = @id_compra;

            -- paso 3: actualiza el ingreso asociado a esta compra
            SELECT @id_ingreso = id_ingreso
            FROM   ingreso
            WHERE  id_compra = @id_compra;

            IF @id_ingreso IS NOT NULL
            BEGIN
                UPDATE ingreso
                SET    estado           = 1,                    -- aplicado
                       referencia_banco = @numero_referencia,
                       flujo_ingresado  = @monto_pagado
                WHERE  id_ingreso = @id_ingreso;
            END;

            -- paso 4: suma el monto al saldo de la cuenta bancaria
            UPDATE cuenta_bancaria
            SET    saldo_actual = saldo_actual + @monto_pagado
            WHERE  id_cuenta = @id_cuenta;

        COMMIT TRANSACTION;

        -- retorna resumen del pago confirmado
        SELECT p.id_pago, p.id_compra, p.monto_pagado, p.metodo_pago,
               p.fecha_pago, ep.descripcion AS estado_pago,
               cb.nombre_banco, cb.saldo_actual AS nuevo_saldo
        FROM   pago          p
        JOIN   estado_pago   ep ON ep.id_estado = p.estado_pago
        JOIN   cuenta_bancaria cb ON cb.id_cuenta = @id_cuenta
        WHERE  p.id_compra = @id_compra;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO


-- ============================================================
-- TRANSACCIÓN 3: sp_devolver_compra
-- Procesa la devolución completa de una compra ya aplicada:
--   1. Valida que la compra exista y esté en estado aplicado (1)
--   2. Cambia estado_pago en compra     → 'devuelto' (4)
--   3. Cambia estado en pago            → 'devuelto' (4)
--   4. Cambia estado en ingreso         → 'devuelto' (4)
--   5. Reincorpora las unidades al inventario (revierte el descuento de stock)
--   6. Si el producto estaba agotado, lo marca como disponible otra vez
--   7. Resta el monto devuelto del saldo de la cuenta bancaria
-- ============================================================
CREATE OR ALTER PROCEDURE sp_devolver_compra
    @id_compra INT,
    @id_cuenta TINYINT,       -- cuenta desde la que se realiza la devolución
    @motivo    VARCHAR(255) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @monto_devolver  DECIMAL(10,2);
    DECLARE @id_producto     INT;
    DECLARE @cantidad        INT;

    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM compra WHERE id_compra = @id_compra)
            RAISERROR('No existe la compra %d.',16,1,@id_compra);

        -- solo se pueden devolver compras en estado aplicado (1)
        IF NOT EXISTS (SELECT 1 FROM compra WHERE id_compra = @id_compra AND estado_pago = 1)
            RAISERROR('Solo se pueden devolver compras con estado aplicado.',16,1);

        IF NOT EXISTS (SELECT 1 FROM cuenta_bancaria WHERE id_cuenta = @id_cuenta)
            RAISERROR('No existe la cuenta bancaria %d.',16,1,@id_cuenta);

        SELECT @monto_devolver = monto_total FROM compra WHERE id_compra = @id_compra;

        -- valida que la cuenta tenga saldo suficiente para la devolución
        IF (SELECT saldo_actual FROM cuenta_bancaria WHERE id_cuenta = @id_cuenta) < @monto_devolver
            RAISERROR('Saldo insuficiente en la cuenta %d para realizar la devolución.',16,1,@id_cuenta);

        BEGIN TRANSACTION;

            -- paso 1: marca la compra como devuelta (4)
            UPDATE compra
            SET    estado_pago  = 4,
                   comentarios  = ISNULL(comentarios,'') + ' | DEVOLUCIÓN: ' + ISNULL(@motivo,'Sin motivo')
            WHERE  id_compra = @id_compra;

            -- paso 2: marca el pago como devuelto (4)
            UPDATE pago
            SET    estado_pago = 4,
                   notas       = ISNULL(notas,'') + ' | Devolución procesada'
            WHERE  id_compra = @id_compra;

            -- paso 3: marca el ingreso como devuelto (4)
            UPDATE ingreso
            SET    estado = 4
            WHERE  id_compra = @id_compra;

            -- paso 4: reincorpora unidades al inventario por cada línea del detalle
            DECLARE cur_devol CURSOR LOCAL FAST_FORWARD FOR
                SELECT id_producto, cantidad
                FROM   detalle_compra
                WHERE  id_compra = @id_compra;

            OPEN cur_devol;
            FETCH NEXT FROM cur_devol INTO @id_producto, @cantidad;

            WHILE @@FETCH_STATUS = 0
            BEGIN
                UPDATE inventario
                SET    cantidad_disponible = cantidad_disponible + @cantidad,
                       unidades_vendidas   = unidades_vendidas   - @cantidad
                WHERE  id_producto = @id_producto;

                -- si el producto estaba agotado (2), lo reactiva como disponible (1)
                IF EXISTS (SELECT 1 FROM producto WHERE id_producto = @id_producto AND disponibilidad = 2)
                    UPDATE producto
                    SET    disponibilidad = 1
                    WHERE  id_producto = @id_producto;

                FETCH NEXT FROM cur_devol INTO @id_producto, @cantidad;
            END;

            CLOSE cur_devol;
            DEALLOCATE cur_devol;

            -- paso 5: descuenta el monto devuelto del saldo de la cuenta
            UPDATE cuenta_bancaria
            SET    saldo_actual = saldo_actual - @monto_devolver
            WHERE  id_cuenta = @id_cuenta;

        COMMIT TRANSACTION;

        SELECT 'Devolución procesada correctamente.' AS mensaje,
               @id_compra      AS id_compra,
               @monto_devolver AS monto_devuelto;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO


-- ============================================================
-- TRANSACCIÓN 4: sp_registrar_gasto_y_descontar_saldo
-- Registra un gasto operativo y actualiza el saldo de la cuenta:
--   1. Valida cuenta existente, activa y con saldo suficiente
--   2. Inserta el gasto en gastos
--   3. Descuenta el monto del saldo_actual de la cuenta bancaria
--   4. Si el nuevo saldo cae por debajo de un umbral crítico (10,000),
--      marca la cuenta como 'bloqueada' (3) para alertar al administrador
-- Garantiza que nunca se registre un gasto sin el descuento correspondiente
-- ni se descuente sin haber registrado el gasto.
-- ============================================================
CREATE OR ALTER PROCEDURE sp_registrar_gasto_y_descontar_saldo
    @id_cuenta       TINYINT,
    @responsable     VARCHAR(100) = NULL,
    @fecha_gasto     DATE,
    @descripcion     VARCHAR(255) = NULL,
    @categoria       VARCHAR(100) = NULL,
    @monto           tipo_monto,
    @comprobante     VARCHAR(100) = NULL,
    @notas           VARCHAR(255) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @saldo_actual   DECIMAL(10,2);
    DECLARE @nuevo_saldo    DECIMAL(10,2);
    DECLARE @estado_cuenta  INT;

    BEGIN TRY
        IF @id_cuenta   IS NULL RAISERROR('id_cuenta no puede ser NULL.',16,1);
        IF @fecha_gasto IS NULL RAISERROR('fecha_gasto no puede ser NULL.',16,1);
        IF @monto       IS NULL RAISERROR('monto no puede ser NULL.',16,1);

        IF NOT EXISTS (SELECT 1 FROM cuenta_bancaria WHERE id_cuenta = @id_cuenta)
            RAISERROR('No existe la cuenta bancaria %d.',16,1,@id_cuenta);

        -- valida que la cuenta esté activa (1); no se puede gastar de una cuenta bloqueada/inactiva
        SELECT @saldo_actual  = saldo_actual,
               @estado_cuenta = estado
        FROM   cuenta_bancaria
        WHERE  id_cuenta = @id_cuenta;

        IF @estado_cuenta <> 1
            RAISERROR('La cuenta bancaria %d no está activa.',16,1,@id_cuenta);

        -- valida saldo suficiente para cubrir el gasto
        IF @saldo_actual < @monto
            DECLARE @saldo_str VARCHAR(20) = CAST(@saldo_actual AS VARCHAR(20));
            DECLARE @monto_str VARCHAR(20) = CAST(@monto AS VARCHAR(20));
            RAISERROR('Saldo insuficiente en la cuenta %d. Saldo: %s | Gasto: %s.',
                      16, 1, @id_cuenta, @saldo_str, @monto_str);

        SET @nuevo_saldo = @saldo_actual - @monto;

        BEGIN TRANSACTION;

            -- paso 1: inserta el gasto
            INSERT INTO gastos (id_cuenta, responsable, fecha_registro, fecha_gasto,
                                descripcion, categoria, monto, comprobante, notas)
            VALUES (@id_cuenta, @responsable, GETDATE(), @fecha_gasto,
                    @descripcion, @categoria, @monto, @comprobante, @notas);

            -- paso 2: descuenta el monto del saldo
            UPDATE cuenta_bancaria
            SET    saldo_actual = @nuevo_saldo
            WHERE  id_cuenta = @id_cuenta;

            -- paso 3: si el nuevo saldo cae por debajo del umbral crítico, bloquea la cuenta
            IF @nuevo_saldo < 10000.00
                UPDATE cuenta_bancaria
                SET    estado = 3   -- bloqueada
                WHERE  id_cuenta = @id_cuenta;

        COMMIT TRANSACTION;

        -- retorna resumen del gasto y estado actualizado de la cuenta
        SELECT g.id_gastos, g.monto, g.fecha_gasto, g.categoria,
               cb.saldo_actual AS saldo_resultante,
               ec.descripcion  AS estado_cuenta
        FROM   gastos          g
        JOIN   cuenta_bancaria cb ON cb.id_cuenta = g.id_cuenta
        JOIN   estado_cuenta   ec ON ec.id_estado = cb.estado
        WHERE  g.id_gastos = SCOPE_IDENTITY();

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO


-- ============================================================
-- TRANSACCIÓN 5: sp_transferir_entre_cuentas
-- Transfiere un monto de una cuenta bancaria a otra:
--   1. Valida que ambas cuentas existan y estén activas
--   2. Valida que la cuenta origen tenga saldo suficiente
--   3. Descuenta el monto de la cuenta origen
--   4. Suma el monto a la cuenta destino
--   5. Registra el movimiento como gasto en la cuenta origen
--      y como ingreso en la cuenta destino ligado a una compra dummy
-- Ambas actualizaciones de saldo ocurren en la misma transacción:
-- si una falla, ninguna se aplica.
-- ============================================================
CREATE OR ALTER PROCEDURE sp_transferir_entre_cuentas
    @id_cuenta_origen  TINYINT,
    @id_cuenta_destino TINYINT,
    @monto             DECIMAL(10,2),
    @descripcion       VARCHAR(255) = NULL,
    @responsable       VARCHAR(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;
 
    DECLARE @saldo_origen   DECIMAL(10,2);
    DECLARE @estado_origen  INT;
    DECLARE @estado_destino INT;
 
    BEGIN TRY
        IF @id_cuenta_origen  IS NULL RAISERROR('id_cuenta_origen no puede ser NULL.',16,1);
        IF @id_cuenta_destino IS NULL RAISERROR('id_cuenta_destino no puede ser NULL.',16,1);
        IF @monto IS NULL OR @monto <= 0
            RAISERROR('El monto debe ser mayor a cero.',16,1);
        IF @id_cuenta_origen = @id_cuenta_destino
            RAISERROR('La cuenta origen y destino no pueden ser la misma.',16,1);
 
        IF NOT EXISTS (SELECT 1 FROM cuenta_bancaria WHERE id_cuenta = @id_cuenta_origen)
            RAISERROR('No existe la cuenta origen %d.',16,1,@id_cuenta_origen);
        IF NOT EXISTS (SELECT 1 FROM cuenta_bancaria WHERE id_cuenta = @id_cuenta_destino)
            RAISERROR('No existe la cuenta destino %d.',16,1,@id_cuenta_destino);
 
        -- valida que ambas cuentas estén activas (1)
        SELECT @saldo_origen  = saldo_actual,
               @estado_origen = estado
        FROM   cuenta_bancaria
        WHERE  id_cuenta = @id_cuenta_origen;
 
        SELECT @estado_destino = estado
        FROM   cuenta_bancaria
        WHERE  id_cuenta = @id_cuenta_destino;
 
        IF @estado_origen <> 1
            RAISERROR('La cuenta origen %d no está activa.',16,1,@id_cuenta_origen);
        IF @estado_destino <> 1
            RAISERROR('La cuenta destino %d no está activa.',16,1,@id_cuenta_destino);
 
        IF @saldo_origen < @monto
        DECLARE @saldo_origen_temp VARCHAR(20) = CAST(@saldo_origen AS VARCHAR(20));
        DECLARE @monto_temp VARCHAR(20) = CAST(@monto AS VARCHAR(20));
            RAISERROR('Saldo insuficiente en la cuenta origen %d. Saldo: %.2f | Transferencia: %.2f.',
                      16,1,@id_cuenta_origen,@saldo_origen_temp,@monto_temp);

        BEGIN TRANSACTION;
 
            -- paso 1: registra el gasto antes de modificar el saldo.
            -- el trigger trg_after_insert_gastos se dispara aquí y lee
            -- saldo_actual con su valor original (aún no decrementado).
            INSERT INTO gastos (id_cuenta, responsable, fecha_registro, fecha_gasto,
                                descripcion, categoria, monto, notas)
            VALUES (@id_cuenta_origen, @responsable, GETDATE(), GETDATE(),
                    ISNULL(@descripcion,'Transferencia entre cuentas'),
                    'Transferencia',
                    @monto,
                    'Transferencia hacia cuenta ' + CAST(@id_cuenta_destino AS VARCHAR(5)));
 
            -- paso 2: descuenta el monto de la cuenta origen
            UPDATE cuenta_bancaria
            SET    saldo_actual = saldo_actual - @monto
            WHERE  id_cuenta = @id_cuenta_origen;
 
            -- paso 3: suma el monto a la cuenta destino
            UPDATE cuenta_bancaria
            SET    saldo_actual = saldo_actual + @monto
            WHERE  id_cuenta = @id_cuenta_destino;
 
        COMMIT TRANSACTION;
 
        -- retorna saldos actualizados de ambas cuentas
        SELECT cb.id_cuenta,
               cb.nombre_banco,
               cb.tipo_cuenta,
               cb.saldo_actual,
               ec.descripcion AS estado
        FROM   cuenta_bancaria cb
        JOIN   estado_cuenta   ec ON ec.id_estado = cb.estado
        WHERE  cb.id_cuenta IN (@id_cuenta_origen, @id_cuenta_destino)
        ORDER  BY cb.id_cuenta;
 
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO










-- =============================================================================
-- consultas avanzadas
-- Cinco consultas de procesamiento avanzado. Cada una cruza al menos
-- cuatro tablas y usa técnicas como CTEs, funciones de ventana,
-- subconsultas correlacionadas u OUTER APPLY.
-- =============================================================================

-- ============================================================
-- CONSULTA 1: top 5 productos más vendidos con su rentabilidad
-- muestra los 5 productos con mayor número de unidades vendidas,
-- incluyendo: categoría, material, stock actual, ingresos generados
-- y una columna calculada de rentabilidad por unidad.
-- tablas: producto, detalle_compra, inventario, categoria_producto,
--         tipo_material, compra
-- ============================================================
SELECT TOP 5
    p.id_producto,
    p.nombre                                            AS producto,
    p.codigo,
    cat.nombre                                          AS categoria,
    tm.nombre_material                                           AS material,
    p.precio_venta,
    SUM(dc.cantidad)                                    AS total_unidades_vendidas,
    SUM(dc.cantidad * dc.precio_unitario)               AS ingresos_totales,
    i.cantidad_disponible                               AS stock_actual,
    -- rentabilidad por unidad = precio de venta - precio promedio al que se vendió
    p.precio_venta - AVG(dc.precio_unitario)            AS diferencia_precio_promedio,
    -- porcentaje del total de ventas que representa este producto
    CAST(
        SUM(dc.cantidad * dc.precio_unitario) * 100.0
        / (SELECT SUM(dc2.cantidad * dc2.precio_unitario)
           FROM   detalle_compra dc2
           JOIN   compra         c2 ON c2.id_compra  = dc2.id_compra
           WHERE  c2.estado_pago = 1)   -- solo ventas aplicadas
    AS DECIMAL(5,2))                                    AS pct_ingresos_totales
FROM       producto         p
JOIN       detalle_compra   dc  ON dc.id_producto  = p.id_producto
JOIN       compra           c   ON c.id_compra     = dc.id_compra
JOIN       inventario       i   ON i.id_producto   = p.id_producto
JOIN       categoria_producto cat ON cat.id_categoria = p.id_categoria
JOIN       tipo_material    tm  ON tm.id_material  = p.material
WHERE      c.estado_pago = 1   -- solo compras con pago aplicado
GROUP BY   p.id_producto, p.nombre, p.codigo, cat.nombre,
           tm.nombre_material, p.precio_venta, i.cantidad_disponible
ORDER BY   total_unidades_vendidas DESC;
GO


-- ============================================================
-- CONSULTA 2: alertas de stock bajo con historial de ventas reciente
-- lista todos los productos cuyo stock actual está por debajo del
-- mínimo definido en inventario:
--   • unidades vendidas en los últimos 30 días
--   • fecha de la última venta
--   • estado actual del inventario
--   • urgencia calculada (crítico / bajo / normal)
-- tablas: inventario, producto, categoria_producto, detalle_compra,
--         compra, estado_inventario
-- ============================================================
SELECT
    p.id_producto,
    p.nombre                                            AS producto,
    p.codigo,
    cat.nombre                                          AS categoria,
    ei.descripcion                                      AS estado_inventario,
    i.cantidad_disponible                               AS stock_actual,
    i.cantidad_minima,
    i.cantidad_maxima,
    i.unidades_vendidas                                 AS total_vendido_historico,
    -- ventas en los últimos 30 días
    ISNULL(v30.unidades_30d, 0)                         AS unidades_vendidas_30d,
    v30.ultima_venta,
    -- nivel de urgencia según qué tan por debajo del mínimo está el stock
    CASE
        WHEN i.cantidad_disponible = 0
            THEN 'CRITICO — AGOTADO'
        WHEN i.cantidad_disponible <= i.cantidad_minima / 2
            THEN 'CRITICO — BAJO MITAD DEL MINIMO'
        WHEN i.cantidad_disponible < i.cantidad_minima
            THEN 'BAJO — POR DEBAJO DEL MINIMO'
        ELSE 'NORMAL'
    END                                                 AS nivel_urgencia,
    -- unidades que faltan para llegar al mínimo
    CASE WHEN i.cantidad_disponible < i.cantidad_minima
         THEN i.cantidad_minima - i.cantidad_disponible
         ELSE 0
    END                                                 AS unidades_a_reponer
FROM       inventario       i
JOIN       producto         p   ON p.id_producto   = i.id_producto
JOIN       categoria_producto cat ON cat.id_categoria = p.id_categoria
JOIN       estado_inventario ei  ON ei.id_estado   = i.estado
-- subconsulta lateral: ventas recientes del producto
OUTER APPLY (
    SELECT
        SUM(dc.cantidad)    AS unidades_30d,
        MAX(c.fecha_compra) AS ultima_venta
    FROM   detalle_compra dc
    JOIN   compra         c  ON c.id_compra  = dc.id_compra
    WHERE  dc.id_producto  = i.id_producto
      AND  c.estado_pago   = 1
      AND  c.fecha_compra >= DATEADD(DAY, -30, GETDATE())
) v30
WHERE i.cantidad_disponible < i.cantidad_minima
ORDER BY nivel_urgencia, unidades_a_reponer DESC;
GO


-- ============================================================
-- CONSULTA 3: historial completo de un cliente con ranking
-- genera un reporte por cliente que incluye:
--   • datos de contacto (email, teléfono)
--   • distrito, cantón y provincia
--   • total de compras, monto acumulado y fecha de última compra
--   • ranking de clientes por monto acumulado (window function)
--   • clasificación de cliente (premium / frecuente / ocasional / nuevo)
-- tablas: cliente, email, telefonos, direccion, distritos, cantones,
--         provincias, compra, pago, estado_cliente
-- ============================================================
WITH resumen_compras AS (
    -- agrega el historial de compras por cliente (solo pagos aplicados)
    SELECT
        c.id_cliente,
        COUNT(c.id_compra)              AS total_compras,
        SUM(c.monto_total)              AS monto_acumulado,
        MIN(c.fecha_compra)             AS primera_compra,
        MAX(c.fecha_compra)             AS ultima_compra,
        -- días desde la última compra
        DATEDIFF(DAY, MAX(c.fecha_compra), GETDATE()) AS dias_sin_comprar
    FROM   compra c
    WHERE  c.estado_pago = 1
    GROUP BY c.id_cliente
)
SELECT
    cl.id_cliente,
    cl.nombre + ' ' + cl.apellido1
        + ISNULL(' ' + cl.apellido2, '')            AS nombre_completo,
    ec.descripcion                                  AS estado,
    cl.fecha_registro,
    -- contacto
    em.email,
    t.telefono,
    -- ubicación geográfica completa
    d.distrito,
    cn.canton,
    pr.provincia,
    -- métricas de compra
    ISNULL(rc.total_compras,  0)                    AS total_compras,
    ISNULL(rc.monto_acumulado, 0)                   AS monto_acumulado,
    rc.primera_compra,
    rc.ultima_compra,
    rc.dias_sin_comprar,
    -- ranking por monto acumulado entre todos los clientes
    RANK() OVER (ORDER BY ISNULL(rc.monto_acumulado, 0) DESC) AS ranking_monto,
    -- clasificación de cliente según actividad y monto
    CASE
        WHEN rc.total_compras IS NULL
            THEN 'NUEVO — SIN COMPRAS'
        WHEN rc.monto_acumulado >= 500000 AND rc.dias_sin_comprar <= 90
            THEN 'PREMIUM'
        WHEN rc.total_compras   >= 3      AND rc.dias_sin_comprar <= 180
            THEN 'FRECUENTE'
        WHEN rc.dias_sin_comprar > 180
            THEN 'INACTIVO'
        ELSE 'OCASIONAL'
    END                                             AS clasificacion_cliente
FROM       cliente          cl
JOIN       estado_cliente   ec  ON ec.id_estado    = cl.estado_cliente
-- email principal (el de menor id para ese cliente)
OUTER APPLY (
    SELECT TOP 1 email
    FROM   email
    WHERE  id_cliente = cl.id_cliente
    ORDER  BY id_email
) em
LEFT JOIN  telefonos        t   ON t.id_cliente    = cl.id_cliente
-- primera dirección registrada del cliente
OUTER APPLY (
    SELECT TOP 1 id_distrito
    FROM   direccion
    WHERE  id_cliente = cl.id_cliente
) dir
LEFT JOIN  distritos        d   ON d.id_distrito   = dir.id_distrito
LEFT JOIN  cantones         cn  ON cn.id_canton    = d.canton
LEFT JOIN  provincias       pr  ON pr.id_provincia = cn.provincia
LEFT JOIN  resumen_compras  rc  ON rc.id_cliente   = cl.id_cliente
ORDER BY   ranking_monto;
GO


-- ============================================================
-- CONSULTA 4: resumen financiero mensual por cuenta bancaria
-- genera un estado de resultados mensual que muestra, para cada
-- cuenta bancaria y cada mes:
--   • total de ingresos aplicados
--   • total de egresos (gastos)
--   • balance neto del mes
--   • acumulado progresivo de saldo (running total)
--   • comparación con el mes anterior (variación porcentual)
-- tablas: cuenta_bancaria, ingreso, gastos, estado_cuenta, estado_pago
-- ============================================================
WITH flujos_mensuales AS (
    -- ingresos aplicados por cuenta y mes
    SELECT
        i.id_cuenta,
        YEAR(i.fecha_ingreso)  AS anio,
        MONTH(i.fecha_ingreso) AS mes,
        SUM(i.monto_ingresado) AS total_ingresos,
        0.00                   AS total_gastos
    FROM   ingreso i
    WHERE  i.estado = 1   -- solo ingresos aplicados
    GROUP BY i.id_cuenta, YEAR(i.fecha_ingreso), MONTH(i.fecha_ingreso)

    UNION ALL

    -- gastos por cuenta y mes
    SELECT
        g.id_cuenta,
        YEAR(g.fecha_gasto)    AS anio,
        MONTH(g.fecha_gasto)   AS mes,
        0.00                   AS total_ingresos,
        SUM(g.monto)           AS total_gastos
    FROM   gastos g
    GROUP BY g.id_cuenta, YEAR(g.fecha_gasto), MONTH(g.fecha_gasto)
),
resumen_mensual AS (
    -- consolida ingresos y gastos en una sola fila por cuenta y mes
    SELECT
        fm.id_cuenta,
        fm.anio,
        fm.mes,
        SUM(fm.total_ingresos)              AS ingresos_mes,
        SUM(fm.total_gastos)                AS gastos_mes,
        SUM(fm.total_ingresos)
            - SUM(fm.total_gastos)          AS balance_neto
    FROM   flujos_mensuales fm
    GROUP BY fm.id_cuenta, fm.anio, fm.mes
)
SELECT
    cb.nombre_banco,
    cb.tipo_cuenta,
    cb.titular,
    ec.descripcion                          AS estado_cuenta,
    rm.anio,
    rm.mes,
    rm.ingresos_mes,
    rm.gastos_mes,
    rm.balance_neto,
    cb.saldo_actual                         AS saldo_vigente,
    -- acumulado progresivo del balance neto dentro de la misma cuenta
    SUM(rm.balance_neto) OVER (
        PARTITION BY rm.id_cuenta
        ORDER BY rm.anio, rm.mes
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    )                                       AS balance_acumulado,
    -- variación porcentual del balance neto respecto al mes anterior
    LAG(rm.balance_neto) OVER (
        PARTITION BY rm.id_cuenta
        ORDER BY rm.anio, rm.mes
    )                                       AS balance_mes_anterior,
    CASE
        WHEN LAG(rm.balance_neto) OVER (
                 PARTITION BY rm.id_cuenta
                 ORDER BY rm.anio, rm.mes) IS NULL
            THEN NULL
        WHEN LAG(rm.balance_neto) OVER (
                 PARTITION BY rm.id_cuenta
                 ORDER BY rm.anio, rm.mes) = 0
            THEN NULL
        ELSE CAST(
            (rm.balance_neto - LAG(rm.balance_neto) OVER (
                PARTITION BY rm.id_cuenta ORDER BY rm.anio, rm.mes))
            * 100.0
            / ABS(LAG(rm.balance_neto) OVER (
                PARTITION BY rm.id_cuenta ORDER BY rm.anio, rm.mes))
        AS DECIMAL(8,2))
    END                                     AS variacion_pct_vs_mes_anterior
FROM       resumen_mensual  rm
JOIN       cuenta_bancaria  cb  ON cb.id_cuenta = rm.id_cuenta
JOIN       estado_cuenta    ec  ON ec.id_estado = cb.estado
ORDER BY   cb.id_cuenta, rm.anio, rm.mes;
GO


-- ============================================================
-- CONSULTA 5 — deudas pendientes y antigüedad de cartera
-- ============================================================
WITH cartera_pendiente AS (
    -- compras en estado pendiente que aún no tienen pago aplicado
    SELECT
        c.id_compra,
        c.id_cliente,
        c.numero_factura,
        c.fecha_compra,
        c.monto_total,
        DATEDIFF(DAY, c.fecha_compra, GETDATE()) AS dias_pendiente,
        i.metodo_pago                            AS metodo_pago_registrado
    FROM   compra   c
    LEFT   JOIN ingreso i ON i.id_compra = c.id_compra
    WHERE  c.estado_pago = 2   -- pendiente
),
metodo_frecuente AS (
    -- método de pago más usado por cada cliente en compras ya aplicadas.
    -- primero se pre-agrega el conteo por (id_cliente, metodo_pago),
    -- luego FIRST_VALUE ordena por ese conteo.
    SELECT DISTINCT
        id_cliente,
        FIRST_VALUE(metodo_pago) OVER (
            PARTITION BY id_cliente
            ORDER BY cnt DESC, metodo_pago
        ) AS metodo_preferido
    FROM (
        SELECT
            id_cliente,
            metodo_pago,
            COUNT(id_pago) AS cnt
        FROM   pago
        WHERE  estado_pago = 1
        GROUP BY id_cliente, metodo_pago
    ) conteo
),
totales AS (
    -- total pendiente global para calcular el porcentaje por cliente
    SELECT SUM(monto_total) AS gran_total_pendiente
    FROM   cartera_pendiente
)
SELECT
    cp.id_compra,
    cp.numero_factura,
    cl.nombre + ' ' + cl.apellido1
        + ISNULL(' ' + cl.apellido2,'')         AS cliente,
    em.email,
    cp.fecha_compra,
    cp.monto_total                              AS monto_pendiente,
    cp.dias_pendiente,
    -- clasificación por antigüedad de mora
    CASE
        WHEN cp.dias_pendiente = 0
            THEN 'AL DIA'
        WHEN cp.dias_pendiente BETWEEN 1 AND 30
            THEN 'MORA 1-30 DIAS'
        WHEN cp.dias_pendiente BETWEEN 31 AND 60
            THEN 'MORA 31-60 DIAS'
        ELSE 'VENCIDO > 60 DIAS'
    END                                         AS tramo_mora,
    -- total pendiente por cliente (en caso de tener varias compras sin pagar)
    SUM(cp.monto_total) OVER (
        PARTITION BY cp.id_cliente
    )                                           AS total_pendiente_cliente,
    -- porcentaje de la cartera total que representa este cliente
    CAST(
        SUM(cp.monto_total) OVER (PARTITION BY cp.id_cliente)
        * 100.0
        / t.gran_total_pendiente
    AS DECIMAL(5,2))                            AS pct_cartera,
    cp.metodo_pago_registrado,
    ISNULL(mf.metodo_preferido, 'Sin historial') AS metodo_preferido_cliente
FROM       cartera_pendiente cp
CROSS JOIN totales           t
JOIN       cliente           cl  ON cl.id_cliente = cp.id_cliente
-- email principal del cliente
OUTER APPLY (
    SELECT TOP 1 email
    FROM   email
    WHERE  id_cliente = cp.id_cliente
    ORDER  BY id_email
) em
LEFT JOIN  metodo_frecuente  mf  ON mf.id_cliente = cp.id_cliente
ORDER BY   tramo_mora DESC, cp.monto_total DESC;
GO

-- ============================================================
-- resumen de consultas implementadas:
--
-- Q1: top 5 productos más vendidos con rentabilidad
--     tablas: producto, detalle_compra, inventario,
--             categoria_producto, tipo_material, compra
--     técnicas: subconsulta escalar, GROUP BY + HAVING implícito,
--               TOP, porcentaje sobre total
--
-- Q2: alertas de stock bajo con historial de ventas reciente
--     tablas: inventario, producto, categoria_producto,
--             detalle_compra, compra, estado_inventario
--     técnicas: OUTER APPLY, DATEADD, CASE multinivel, ISNULL
--
-- Q3: historial completo de cliente con ranking
--     tablas: cliente, email, telefonos, direccion, distritos,
--             cantones, provincias, compra, pago, estado_cliente
--     técnicas: CTE, RANK() OVER, OUTER APPLY TOP 1,
--               DATEDIFF, clasificación por reglas de negocio
--
-- Q4: resumen financiero mensual por cuenta bancaria
--     tablas: cuenta_bancaria, ingreso, gastos, estado_cuenta
--     técnicas: CTE de dos niveles, UNION ALL, SUM() OVER con
--               ROWS BETWEEN (running total), LAG() para variación mensual
--
-- Q5: deudas pendientes y antigüedad de cartera
--     tablas: compra, cliente, ingreso, pago, estado_pago, email
--     técnicas: CTE encadenados, CROSS JOIN para totales globales,
--               SUM() OVER PARTITION, FIRST_VALUE() OVER para
--               método preferido, OUTER APPLY TOP 1
-- ============================================================










-- =============================================================================
-- Vistas
-- Encapsulan consultas multi-tabla frecuentes para simplificar el acceso
-- desde la aplicación. Definidas con CREATE OR ALTER VIEW para permitir
-- actualizaciones sin DROP previo.
-- La aplicación web consume directamente estas tres vistas.
-- =============================================================================

-- ============================================================
-- VISTA 1: vw_inventario_alertas
-- proporciona un panel completo del estado del inventario para
-- todos los productos del catálogo.
-- para cada producto muestra: categoría, material, disponibilidad,
-- estado del inventario, niveles de stock, métricas calculadas
-- (% de stock disponible, unidades a reponer) y una clasificación
-- automática de alerta según la posición actual respecto al mínimo.
-- se usa para detectar productos que requieren reposición urgente
-- y para el módulo de inventario de la aplicación web.
-- tablas involucradas:
--   inventario, producto, categoria_producto, activa_inventario,
--   tipo_material, estado_inventario, disponible_inventario
-- ============================================================
CREATE OR ALTER VIEW vw_inventario_alertas
AS
SELECT
    -- identificadores
    p.id_producto,
    p.codigo,
    p.nombre                                                AS producto,
    p.tipo,
    p.descripcion                                           AS descripcion_producto,
    p.precio_venta,
    p.fecha_creacion,

    -- categoría
    cat.id_categoria,
    cat.nombre                                              AS categoria,
    cat.comision_venta,
    ai.descripcion                                          AS categoria_activa,

    -- material
    tm.id_material,
    tm.nombre_material                                      AS material,
    tm.proveedor,

    -- estado del registro de inventario
    ei.descripcion                                          AS estado_inventario,

    -- disponibilidad del producto para venta
    di.descripcion                                          AS disponibilidad_venta,

    -- cantidades
    i.cantidad_disponible,
    i.cantidad_minima,
    i.cantidad_maxima,
    i.unidades_vendidas,

    -- unidades que faltan para alcanzar el mínimo definido;
    -- si el stock está sobre el mínimo, el valor es 0
    CASE
        WHEN i.cantidad_disponible < i.cantidad_minima
            THEN i.cantidad_minima - i.cantidad_disponible
        ELSE 0
    END                                                     AS unidades_a_reponer,

    -- porcentaje del stock máximo que sigue disponible actualmente;
    -- nullif evita división por cero si cantidad_maxima fuera 0
    CAST(
        i.cantidad_disponible * 100.0
        / NULLIF(i.cantidad_maxima, 0)
    AS DECIMAL(5, 2))                                       AS pct_stock_disponible,

    -- porcentaje del stock máximo que ya fue vendido históricamente
    CAST(
        i.unidades_vendidas * 100.0
        / NULLIF(i.cantidad_maxima, 0)
    AS DECIMAL(5, 2))                                       AS pct_stock_vendido,

    -- cuántas veces el stock actual cubre el mínimo requerido;
    -- útil para saber si hay margen antes de llegar al punto crítico
    CAST(
        i.cantidad_disponible * 1.0
        / NULLIF(i.cantidad_minima, 0)
    AS DECIMAL(5, 2))                                       AS ratio_cobertura_minimo,

    -- clasificación automática de alerta:
    --   agotado          → sin stock (prioridad máxima)
    --   crítico bajo     → bajo la mitad del mínimo
    --   bajo mínimo      → entre mitad y mínimo
    --   lleno            → en el máximo (posible sobrestock)
    --   normal           → dentro del rango saludable
    CASE
        WHEN i.cantidad_disponible = 0
            THEN 'CRITICO — AGOTADO'
        WHEN i.cantidad_disponible <= i.cantidad_minima / 2
            THEN 'CRITICO — BAJO MITAD DEL MINIMO'
        WHEN i.cantidad_disponible < i.cantidad_minima
            THEN 'BAJO — POR DEBAJO DEL MINIMO'
        WHEN i.cantidad_disponible = i.cantidad_maxima
            THEN 'LLENO — EN MAXIMO'
        ELSE 'NORMAL'
    END                                                     AS nivel_alerta
FROM       inventario           i
JOIN       producto             p   ON p.id_producto   = i.id_producto
JOIN       categoria_producto   cat ON cat.id_categoria = p.id_categoria
JOIN       activa_inventario    ai  ON ai.id_estado     = cat.activa
JOIN       tipo_material        tm  ON tm.id_material   = p.material
JOIN       estado_inventario    ei  ON ei.id_estado     = i.estado
JOIN       disponible_inventario di ON di.id_estado     = p.disponibilidad;
GO


-- ============================================================
-- VISTA 2: vw_historial_ventas
-- presenta el historial completo de ventas a nivel de línea de
-- detalle: cada fila es un producto dentro de una compra.
-- cada línea con datos del cliente (nombre, contacto,
-- ubicación geográfica), del producto (categoría, material),
-- del estado de la compra, y del método de cobro registrado en
-- el ingreso correspondiente.
-- incluye columnas calculadas: subtotal de la línea, diferencia
-- entre el precio de catálogo actual y el precio al que se vendió.
-- se usa para reportes de ventas, análisis de márgenes y el
-- módulo de ventas de la aplicación web.
-- tablas involucradas:
--   detalle_compra, compra, cliente, email, telefonos,
--   direccion, distritos, cantones, provincias,
--   producto, categoria_producto, tipo_material,
--   estado_pago, ingreso
-- ============================================================
CREATE OR ALTER VIEW vw_historial_ventas
AS
SELECT
    -- identificadores de la venta
    c.id_compra,
    c.numero_factura,
    c.fecha_compra,
    c.monto_total                                           AS monto_total_compra,
    ep.descripcion                                          AS estado_pago_compra,

    -- línea de detalle
    dc.id_producto,
    dc.cantidad,
    dc.precio_unitario,
    -- subtotal de esta línea (cantidad × precio al que se vendió)
    dc.cantidad * dc.precio_unitario                        AS subtotal_linea,

    -- diferencia entre el precio de catálogo vigente y el precio cobrado;
    -- positivo → se vendió más barato que el catálogo actual
    -- negativo → se vendió más caro (precio del catálogo bajó después)
    p.precio_venta - dc.precio_unitario                     AS diferencia_vs_catalogo,

    -- datos del producto
    p.nombre                                                AS producto,
    p.codigo,
    p.tipo                                                  AS tipo_joya,
    cat.nombre                                              AS categoria,
    cat.comision_venta,
    tm.nombre_material                                      AS material,

    -- datos del cliente
    cl.id_cliente,
    cl.nombre + ' ' + cl.apellido1
        + ISNULL(' ' + cl.apellido2, '')                    AS cliente,
    cl.fecha_registro                                       AS cliente_desde,

    -- email y teléfono del cliente (primero registrado en caso de múltiples)
    em.email,
    t.telefono,

    -- ubicación geográfica del cliente (primer distrito registrado)
    d.distrito                                              AS distrito_cliente,
    cn.canton                                               AS canton_cliente,
    pr.provincia                                            AS provincia_cliente,

    -- método de cobro y referencia bancaria del ingreso asociado a esta compra;
    -- outer apply devuelve null si la compra todavía no tiene ingreso registrado
    ing.metodo_pago                                         AS metodo_cobro,
    ing.referencia_banco,
    ing.fecha_ingreso
FROM       detalle_compra       dc
JOIN       compra               c   ON c.id_compra      = dc.id_compra
JOIN       estado_pago          ep  ON ep.id_estado      = c.estado_pago
JOIN       cliente              cl  ON cl.id_cliente     = c.id_cliente
JOIN       producto             p   ON p.id_producto     = dc.id_producto
JOIN       categoria_producto   cat ON cat.id_categoria  = p.id_categoria
JOIN       tipo_material        tm  ON tm.id_material    = p.material
-- email principal: el de menor id_email para ese cliente
OUTER APPLY (
    SELECT TOP 1 email
    FROM   email
    WHERE  id_cliente = cl.id_cliente
    ORDER  BY id_email
) em
-- teléfono del cliente (relación 1:1, pk = id_cliente)
LEFT JOIN  telefonos            t   ON t.id_cliente      = cl.id_cliente
-- primer distrito registrado del cliente
OUTER APPLY (
    SELECT TOP 1 id_distrito
    FROM   direccion
    WHERE  id_cliente = cl.id_cliente
) dir
LEFT JOIN  distritos            d   ON d.id_distrito     = dir.id_distrito
LEFT JOIN  cantones             cn  ON cn.id_canton      = d.canton
LEFT JOIN  provincias           pr  ON pr.id_provincia   = cn.provincia
-- ingreso asociado a la compra (puede no existir aún si está pendiente)
OUTER APPLY (
    SELECT TOP 1
        metodo_pago,
        referencia_banco,
        fecha_ingreso
    FROM   ingreso
    WHERE  id_compra = c.id_compra
    ORDER  BY id_ingreso
) ing;
GO


-- ============================================================ VISTA 3 — vw_estado_financiero

CREATE OR ALTER VIEW vw_estado_financiero
AS
WITH ingresos_por_cuenta AS (
    -- agrega los ingresos de cada cuenta separados por estado:
    --   1 = aplicado (cobrado efectivamente)
    --   2 = pendiente (por confirmar)
    --   4 = devuelto  (revertido)
    SELECT
        id_cuenta,
        SUM(CASE WHEN estado = 1 THEN monto_ingresado ELSE 0 END) AS total_aplicados,
        SUM(CASE WHEN estado = 2 THEN monto_ingresado ELSE 0 END) AS total_pendientes,
        SUM(CASE WHEN estado = 4 THEN monto_ingresado ELSE 0 END) AS total_devueltos,
        COUNT(CASE WHEN estado = 1 THEN 1 END)                     AS qty_ingresos_aplicados,
        COUNT(CASE WHEN estado = 2 THEN 1 END)                     AS qty_ingresos_pendientes,
        MAX(fecha_ingreso)                                          AS fecha_ultimo_ingreso
    FROM   ingreso
    GROUP BY id_cuenta
),
gastos_por_cuenta AS (
    -- agrega los egresos operativos por cuenta bancaria.
    -- ahora agrupa solo por id_cuenta (una fila por cuenta).
    -- la categoría dominante se obtiene con una subconsulta TOP 1
    -- ordenada por frecuencia
    SELECT
        id_cuenta,
        SUM(monto)       AS total_gastos,
        COUNT(id_gastos) AS qty_gastos,
        MAX(fecha_gasto) AS fecha_ultimo_gasto,
        (
            SELECT TOP 1 g2.categoria
            FROM   gastos g2
            WHERE  g2.id_cuenta   = g.id_cuenta
              AND  g2.categoria IS NOT NULL
            GROUP BY g2.categoria
            ORDER BY COUNT(*) DESC, g2.categoria
        )                AS categoria_gasto_principal
    FROM   gastos g
    GROUP BY id_cuenta
)
SELECT
    -- datos de la cuenta bancaria
    cb.id_cuenta,
    cb.nombre_banco,
    cb.tipo_cuenta,
    cb.titular,
    cb.numero_cuenta,
    cb.iban,
    cb.fecha_apertura,
    ec.descripcion                                          AS estado_cuenta,
 
    -- saldo real registrado en el sistema
    cb.saldo_actual,
 
    -- ingresos por estado
    ISNULL(ic.total_aplicados,          0)                  AS ingresos_aplicados,
    ISNULL(ic.total_pendientes,         0)                  AS ingresos_pendientes,
    ISNULL(ic.total_devueltos,          0)                  AS ingresos_devueltos,
    ISNULL(ic.qty_ingresos_aplicados,   0)                  AS qty_ingresos_aplicados,
    ISNULL(ic.qty_ingresos_pendientes,  0)                  AS qty_ingresos_pendientes,
    ic.fecha_ultimo_ingreso,
 
    -- egresos
    ISNULL(gc.total_gastos,             0)                  AS total_gastos,
    ISNULL(gc.qty_gastos,               0)                  AS qty_gastos,
    gc.fecha_ultimo_gasto,
    gc.categoria_gasto_principal,
 
    -- balance contable calculado: ingresos aplicados menos gastos registrados;
    -- no considera devueltos ni pendientes porque no representan flujo real
    ISNULL(ic.total_aplicados, 0) - ISNULL(gc.total_gastos, 0)
                                                            AS balance_calculado,
 
    -- discrepancia: diferencia entre el saldo real y el balance calculado;
    -- idealmente debe ser 0; si no lo es puede indicar ajustes manuales
    -- o movimientos no registrados en el sistema
    cb.saldo_actual
        - (ISNULL(ic.total_aplicados, 0) - ISNULL(gc.total_gastos, 0))
                                                            AS discrepancia_saldo,
 
    -- porcentaje de los ingresos aplicados que se consumió en gastos;
    -- null si no hay ingresos para evitar división por cero
    CASE
        WHEN ISNULL(ic.total_aplicados, 0) = 0 THEN NULL
        ELSE CAST(
            ISNULL(gc.total_gastos, 0) * 100.0
            / ic.total_aplicados
        AS DECIMAL(5, 2))
    END                                                     AS pct_gastos_sobre_ingresos,
 
    -- ratio de exposición pendiente: qué tanto del flujo ya cobrado
    -- hay todavía sin confirmar (indicador de riesgo de cobro)
    CASE
        WHEN ISNULL(ic.total_aplicados, 0) = 0 THEN NULL
        ELSE CAST(
            ISNULL(ic.total_pendientes, 0) * 100.0
            / ic.total_aplicados
        AS DECIMAL(5, 2))
    END                                                     AS pct_pendiente_vs_aplicado,
 
    -- clasificación de salud financiera por cuenta:
    --   bloqueada      → la cuenta está bloqueada en el sistema
    --   inactiva       → la cuenta fue desactivada
    --   déficit        → los gastos superan los ingresos aplicados
    --   saldo crítico  → saldo real inferior al umbral de alerta (10.000)
    --   saludable      → todo en orden
    CASE
        WHEN cb.estado = 3
            THEN 'BLOQUEADA'
        WHEN cb.estado = 2
            THEN 'INACTIVA'
        WHEN ISNULL(ic.total_aplicados, 0) - ISNULL(gc.total_gastos, 0) < 0
            THEN 'DEFICIT — GASTOS SUPERAN INGRESOS'
        WHEN cb.saldo_actual < 10000.00
            THEN 'SALDO CRITICO — BAJO UMBRAL'
        ELSE 'SALUDABLE'
    END                                                     AS salud_financiera
FROM       cuenta_bancaria      cb
JOIN       estado_cuenta        ec  ON ec.id_estado = cb.estado
LEFT JOIN  ingresos_por_cuenta  ic  ON ic.id_cuenta = cb.id_cuenta
LEFT JOIN  gastos_por_cuenta    gc  ON gc.id_cuenta = cb.id_cuenta;
GO









-- =============================================================================
-- Triggers y Cursores
-- Los tres triggers son AFTER INSERT; usan las tablas lógicas INSERTED/DELETED.
-- Los cursores se declaran FAST_FORWARD (solo lectura, solo avance) para
-- maximizar rendimiento en recorridos secuenciales.
-- =============================================================================

-- ============================================================
-- TRIGGER 1: trg_after_insert_detalle_compra
-- se dispara DESPUÉS de insertar una o varias filas en detalle_compra.
-- propósito: mantener compra.monto_total siempre sincronizado con
-- la suma real de sus líneas de detalle, sin importar si la
-- inserción proviene de sp_registrar_venta_completa o de cualquier
-- otra vía (carga masiva, scripts de prueba, etc.).
-- implementación set-based: un único UPDATE que recalcula el total
-- para TODAS las compras afectadas de una sola vez, haciendo que
-- el trigger sea eficiente incluso con inserciones de múltiples filas.
-- tablas involucradas: detalle_compra (base), compra (actualizada)
-- ============================================================
CREATE OR ALTER TRIGGER trg_after_insert_detalle_compra
ON detalle_compra
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;

    -- recalcula monto_total para cada compra que tuvo al menos una
    -- línea insertada en esta operación.
    -- se suman TODAS las líneas de la compra (no solo las nuevas)
    -- para garantizar un total exacto y no acumulativo.
    UPDATE c
    SET    c.monto_total = resumen.total_real
    FROM   compra c
    JOIN (
        SELECT
            dc.id_compra,
            SUM(dc.cantidad * dc.precio_unitario) AS total_real
        FROM   detalle_compra dc
        -- solo las compras afectadas por esta inserción
        WHERE  dc.id_compra IN (SELECT DISTINCT id_compra FROM INSERTED)
        GROUP BY dc.id_compra
    ) resumen ON resumen.id_compra = c.id_compra;
END;
GO

-- ============================================================
-- TRIGGER 2: trg_after_insert_ingreso
-- se dispara DESPUÉS de insertar uno o varios registros en ingreso.
-- propósito: sincronizar automáticamente el estado y el flujo
-- financiero de la compra asociada y, cuando el ingreso ya viene
-- marcado como aplicado (estado = 1), acreditar el monto en la
-- cuenta bancaria correspondiente.
-- esto cubre dos escenarios:
--   a) inserción con estado = 2 (pendiente): sólo valida que la
--      compra referenciada exista y también esté en estado pendiente,
--      protegiendo la consistencia entre ambas tablas.
--   b) inserción con estado = 1 (aplicado): actualiza compra y
--      acredita el saldo de la cuenta.  este caso no ocurre en
--      sp_registrar_venta_completa (que inserta con estado=2),
--      pero sí puede ocurrir en inserciones directas o en
--      variantes futuras del flujo de registro.
-- tablas involucradas: ingreso (base), compra, cuenta_bancaria
-- ============================================================
CREATE OR ALTER TRIGGER trg_after_insert_ingreso
ON ingreso
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;

    -- ----------------------------------------------------------------
    -- bloque a: ingresos pendientes (estado = 2)
    -- valida que la compra referenciada exista y también esté pendiente.
    -- si la compra ya fue aplicada o devuelta, no corresponde asociarle
    -- un nuevo ingreso pendiente → rechaza la operación.
    -- ----------------------------------------------------------------
    IF EXISTS (
        SELECT 1
        FROM   INSERTED i
        JOIN   compra   c ON c.id_compra = i.id_compra
        WHERE  i.estado  = 2
          AND  c.estado_pago NOT IN (1, 2)   -- solo aplicado o pendiente son válidos
    )
    BEGIN
        ROLLBACK TRANSACTION;
        RAISERROR(
            'No se puede registrar un ingreso pendiente para una compra devuelta o rechazada.',
            16, 1
        );
        RETURN;
    END;

    -- ----------------------------------------------------------------
    -- bloque b: ingresos aplicados (estado = 1) insertados directamente
    -- actualiza la compra y acredita el saldo de la cuenta.
    -- ----------------------------------------------------------------

    -- marca la compra como aplicada y registra el flujo de ingreso
    UPDATE c
    SET    c.estado_pago    = 1,
           c.flujo_ingresos = i.monto_ingresado
    FROM   compra   c
    JOIN   INSERTED i ON i.id_compra = c.id_compra
    WHERE  i.estado = 1;

    -- acredita en la cuenta bancaria el total de ingresos aplicados
    -- agrupados por cuenta (por si se insertan varios a la vez)
    UPDATE cb
    SET    cb.saldo_actual = cb.saldo_actual + agg.total_aplicado
    FROM   cuenta_bancaria cb
    JOIN (
        SELECT
            id_cuenta,
            SUM(monto_ingresado) AS total_aplicado
        FROM   INSERTED
        WHERE  estado = 1
        GROUP BY id_cuenta
    ) agg ON agg.id_cuenta = cb.id_cuenta;
END;
GO


-- ============================================================
-- TRIGGER 3: trg_after_insert_gastos
-- se dispara DESPUÉS de insertar uno o varios registros en gastos.
-- propósito: actuar como última línea de defensa ante inserciones
-- directas (que no pasan por sp_registrar_gasto_y_descontar_saldo)
-- garantizando dos invariantes del negocio:
--   1. ningún gasto puede registrarse si el saldo actual de la
--      cuenta es insuficiente para cubrirlo → si lo es, cancela
--      la operación completa con ROLLBACK.
--   2. si el saldo hipotético (saldo_actual - monto) cae por
--      debajo del umbral crítico de ₡10.000, bloquea la cuenta
--      automáticamente (estado = 3), de manera consistente con
--      la lógica de sp_registrar_gasto_y_descontar_saldo.
-- cuando la inserción proviene del sp, la validación de saldo
-- ya fue ejecutada antes de la transacción, por lo que el check
-- del trigger nunca activará el rollback en ese flujo. el bloqueo
-- de cuenta puede dispararse en ambos flujos y es idempotente.
-- tablas involucradas: gastos (base), cuenta_bancaria
-- ============================================================
CREATE OR ALTER TRIGGER trg_after_insert_gastos
ON gastos
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;

    -- ----------------------------------------------------------------
    -- validación 1: saldo insuficiente
    -- compara el saldo actual de la cuenta con el monto del gasto.
    -- en el flujo del sp, el saldo aún no fue decrementado cuando este
    -- trigger se ejecuta, por lo que saldo_actual refleja el valor previo
    -- al gasto. si saldo_actual < monto, la cuenta no puede cubrirlo.
    -- ----------------------------------------------------------------
    IF EXISTS (
        SELECT 1
        FROM   INSERTED        i
        JOIN   cuenta_bancaria cb ON cb.id_cuenta = i.id_cuenta
        WHERE  cb.saldo_actual < i.monto
    )
    BEGIN
        ROLLBACK TRANSACTION;
        RAISERROR(
            'Saldo insuficiente en la cuenta bancaria para cubrir el gasto registrado. Operacion cancelada.',
            16, 1
        );
        RETURN;
    END;

    -- ----------------------------------------------------------------
    -- validación 2: bloqueo preventivo de cuenta con saldo crítico
    -- calcula el saldo hipotético (saldo_actual - monto_del_gasto).
    -- si queda por debajo de ₡10.000, cambia el estado a bloqueada (3).
    -- solo actúa sobre cuentas activas (estado = 1) para no sobreescribir
    -- cuentas ya inactivas (estado = 2) que no deben ser reactivadas aquí.
    -- ----------------------------------------------------------------
    UPDATE cb
    SET    cb.estado = 3   -- bloqueada
    FROM   cuenta_bancaria cb
    JOIN   INSERTED        i  ON i.id_cuenta = cb.id_cuenta
    WHERE  cb.saldo_actual - i.monto < 10000.00
      AND  cb.estado = 1;
END;
GO


-- ============================================================
-- CURSOR 1: cur_reporte_alertas_stock
-- (encapsulado en sp_reporte_alertas_stock)
-- recorre todos los productos cuyo stock actual está por debajo
-- del mínimo definido en inventario.
-- para cada producto en alerta el cursor:
--   1. recopila datos del producto, categoría y material
--   2. calcula unidades_a_reponer = cantidad_maxima - cantidad_disponible
--   3. estima el costo de reposición usando costo_unitario del material
--   4. actualiza inventario.estado a 3 (revision) si el producto
--      aún tiene estado 1 (activo), señalando que requiere atención
--   5. acumula totales globales del reporte
-- al finalizar retorna:
--   • tabla de detalle de todos los productos en alerta
--   • fila de resumen con totales del inventario crítico
-- tablas involucradas: inventario, producto, categoria_producto,
--                      tipo_material, estado_inventario
-- ============================================================
CREATE OR ALTER PROCEDURE sp_reporte_alertas_stock
AS
BEGIN
    SET NOCOUNT ON;

    -- variables del cursor
    DECLARE @id_producto         INT;
    DECLARE @nombre_producto     VARCHAR(100);
    DECLARE @codigo              VARCHAR(50);
    DECLARE @tipo                VARCHAR(50);
    DECLARE @nombre_categoria    VARCHAR(100);
    DECLARE @nombre_material     VARCHAR(100);
    DECLARE @costo_unitario_mat  TINYINT;
    DECLARE @estado_inv          INT;
    DECLARE @cant_disponible     INT;
    DECLARE @cant_minima         INT;
    DECLARE @cant_maxima         INT;

    -- variables de cálculo por iteración
    DECLARE @unidades_a_reponer  INT;
    DECLARE @costo_reposicion    DECIMAL(12, 2);
    DECLARE @nivel_alerta        VARCHAR(50);

    -- acumuladores del reporte global
    DECLARE @total_productos_alerta INT      = 0;
    DECLARE @total_unidades_reponer INT      = 0;
    DECLARE @total_costo_estimado   DECIMAL(12, 2) = 0;
    DECLARE @productos_actualizados INT      = 0;

    -- tabla temporal para acumular los resultados del cursor
    -- y devolverlos todos al final con un único SELECT
    CREATE TABLE #alertas_stock (
        id_producto          INT,
        codigo               VARCHAR(50),
        producto             VARCHAR(100),
        tipo                 VARCHAR(50),
        categoria            VARCHAR(100),
        material             VARCHAR(100),
        cantidad_disponible  INT,
        cantidad_minima      INT,
        cantidad_maxima      INT,
        unidades_a_reponer   INT,
        costo_unitario_mat   TINYINT,
        costo_reposicion_est DECIMAL(12, 2),
        nivel_alerta         VARCHAR(50),
        estado_actualizado   BIT   -- indica si se cambió a estado 'revision'
    );

    BEGIN TRY

        -- cursor local de solo avance para máxima eficiencia de lectura
        DECLARE cur_reporte_alertas_stock CURSOR LOCAL FAST_FORWARD FOR
            SELECT
                p.id_producto,
                p.nombre,
                p.codigo,
                p.tipo,
                cat.nombre                   AS nombre_categoria,
                tm.nombre_material,
                tm.costo_unitario,
                i.estado,
                i.cantidad_disponible,
                i.cantidad_minima,
                i.cantidad_maxima
            FROM       inventario          i
            JOIN       producto            p   ON p.id_producto   = i.id_producto
            JOIN       categoria_producto  cat ON cat.id_categoria = p.id_categoria
            JOIN       tipo_material       tm  ON tm.id_material  = p.material
            WHERE      i.cantidad_disponible < i.cantidad_minima   -- solo productos en alerta
            ORDER BY   i.cantidad_disponible ASC;                  -- más críticos primero

        OPEN cur_reporte_alertas_stock;
        FETCH NEXT FROM cur_reporte_alertas_stock
            INTO @id_producto, @nombre_producto, @codigo, @tipo,
                 @nombre_categoria, @nombre_material, @costo_unitario_mat,
                 @estado_inv, @cant_disponible, @cant_minima, @cant_maxima;

        WHILE @@FETCH_STATUS = 0
        BEGIN
            -- calcula cuántas unidades se deben pedir para llegar al máximo
            SET @unidades_a_reponer = @cant_maxima - @cant_disponible;

            -- estima el costo de reposición con el costo unitario del material
            -- si costo_unitario_mat es NULL usa 0 para no romper el cálculo
            SET @costo_reposicion = @unidades_a_reponer
                                    * ISNULL(@costo_unitario_mat, 0);

            -- clasifica el nivel de urgencia según la profundidad del déficit
            SET @nivel_alerta =
                CASE
                    WHEN @cant_disponible = 0
                        THEN 'CRITICO — AGOTADO'
                    WHEN @cant_disponible <= @cant_minima / 2
                        THEN 'CRITICO — BAJO MITAD DEL MINIMO'
                    ELSE
                        'BAJO — POR DEBAJO DEL MINIMO'
                END;

            -- si el inventario estaba en estado activo (1), lo pasa a
            -- revision (3) para señalar que requiere atención operativa;
            -- descontinuado (2) no se toca porque es un estado definitivo
            IF @estado_inv = 1
            BEGIN
                UPDATE inventario
                SET    estado = 3
                WHERE  id_producto = @id_producto;

                SET @productos_actualizados = @productos_actualizados + 1;
            END;

            -- acumula la fila en la tabla temporal
            INSERT INTO #alertas_stock
            VALUES (
                @id_producto, @codigo, @nombre_producto, @tipo,
                @nombre_categoria, @nombre_material,
                @cant_disponible, @cant_minima, @cant_maxima,
                @unidades_a_reponer, @costo_unitario_mat,
                @costo_reposicion, @nivel_alerta,
                CASE WHEN @estado_inv = 1 THEN 1 ELSE 0 END
            );

            -- actualiza acumuladores globales
            SET @total_productos_alerta = @total_productos_alerta + 1;
            SET @total_unidades_reponer = @total_unidades_reponer + @unidades_a_reponer;
            SET @total_costo_estimado   = @total_costo_estimado   + @costo_reposicion;

            FETCH NEXT FROM cur_reporte_alertas_stock
                INTO @id_producto, @nombre_producto, @codigo, @tipo,
                     @nombre_categoria, @nombre_material, @costo_unitario_mat,
                     @estado_inv, @cant_disponible, @cant_minima, @cant_maxima;
        END;

        CLOSE    cur_reporte_alertas_stock;
        DEALLOCATE cur_reporte_alertas_stock;

        -- resultado 1: detalle de cada producto en alerta
        SELECT *
        FROM   #alertas_stock
        ORDER BY
            CASE nivel_alerta
                WHEN 'CRITICO — AGOTADO'              THEN 1
                WHEN 'CRITICO — BAJO MITAD DEL MINIMO' THEN 2
                ELSE 3
            END,
            cantidad_disponible ASC;

        -- resultado 2: fila de resumen del reporte
        SELECT
            @total_productos_alerta AS productos_en_alerta,
            @total_unidades_reponer AS total_unidades_a_reponer,
            @total_costo_estimado   AS costo_reposicion_estimado,
            @productos_actualizados AS inventarios_marcados_revision;

        DROP TABLE #alertas_stock;

    END TRY
    BEGIN CATCH
        -- limpieza del cursor si quedó abierto por un error
        IF CURSOR_STATUS('local', 'cur_reporte_alertas_stock') >= 0
        BEGIN
            CLOSE     cur_reporte_alertas_stock;
            DEALLOCATE cur_reporte_alertas_stock;
        END;
        IF OBJECT_ID('tempdb..#alertas_stock') IS NOT NULL
            DROP TABLE #alertas_stock;
        THROW;
    END CATCH;
END;
GO


-- ============================================================
-- CURSOR 2: cur_balance_cuentas
-- (encapsulado en sp_balance_cuentas)
-- recorre todas las cuentas bancarias que no están inactivas (estado ≠ 2)
-- y realiza una auditoría financiera completa por cuenta.
-- para cada cuenta el cursor:
--   1. calcula total_ingresos_aplicados (ingreso.estado = 1)
--   2. calcula total_gastos
--   3. obtiene la cantidad de compras pendientes de pago asociadas
--   4. computa balance_calculado = total_ingresos - total_gastos
--   5. detecta discrepancia = saldo_actual - balance_calculado
--   6. aplica lógica de bloqueo / desbloqueo automático:
--        • si está bloqueada (3) y su saldo real >= ₡10.000 → reactiva (1)
--        • si está activa  (1) y su saldo real <  ₡10.000 → bloquea (3)
--   7. acumula totales de la joyería
-- al finalizar retorna:
--   • tabla de auditoría por cuenta con estado resultante
--   • fila de resumen financiero global de soul cr
-- tablas involucradas: cuenta_bancaria, estado_cuenta, ingreso,
--                      gastos, compra
-- ============================================================
CREATE OR ALTER PROCEDURE sp_balance_cuentas
AS
BEGIN
    SET NOCOUNT ON;

    -- variables del cursor
    DECLARE @id_cuenta       TINYINT;
    DECLARE @nombre_banco    VARCHAR(50);
    DECLARE @tipo_cuenta     VARCHAR(50);
    DECLARE @saldo_actual    DECIMAL(10, 2);
    DECLARE @estado_cuenta   INT;
    DECLARE @desc_estado     VARCHAR(20);

    -- variables de cálculo por cuenta
    DECLARE @total_ingresos  DECIMAL(12, 2);
    DECLARE @total_gastos    DECIMAL(12, 2);
    DECLARE @balance_calc    DECIMAL(12, 2);
    DECLARE @discrepancia    DECIMAL(12, 2);
    DECLARE @compras_pend    INT;
    DECLARE @nuevo_estado    INT;
    DECLARE @accion_aplicada VARCHAR(50);

    -- acumuladores globales de soul cr
    DECLARE @gran_total_ingresos DECIMAL(12, 2) = 0;
    DECLARE @gran_total_gastos   DECIMAL(12, 2) = 0;
    DECLARE @saldo_total_real    DECIMAL(12, 2) = 0;
    DECLARE @cuentas_procesadas  INT            = 0;
    DECLARE @cuentas_bloqueadas  INT            = 0;
    DECLARE @cuentas_reactivadas INT            = 0;

    -- tabla temporal para acumular resultados de la auditoría
    CREATE TABLE #balance_cuentas (
        id_cuenta            TINYINT,
        banco                VARCHAR(50),
        tipo_cuenta          VARCHAR(50),
        saldo_real           DECIMAL(12, 2),
        total_ingresos       DECIMAL(12, 2),
        total_gastos         DECIMAL(12, 2),
        balance_calculado    DECIMAL(12, 2),
        discrepancia         DECIMAL(12, 2),
        compras_pendientes   INT,
        estado_anterior      VARCHAR(20),
        estado_resultante    VARCHAR(20),
        accion               VARCHAR(50)
    );

    BEGIN TRY

        -- cursor que recorre las cuentas activas y bloqueadas
        -- (excluye inactivas con estado = 2)
        DECLARE cur_balance_cuentas CURSOR LOCAL FAST_FORWARD FOR
            SELECT
                cb.id_cuenta,
                cb.nombre_banco,
                cb.tipo_cuenta,
                cb.saldo_actual,
                cb.estado,
                ec.descripcion
            FROM   cuenta_bancaria cb
            JOIN   estado_cuenta   ec ON ec.id_estado = cb.estado
            WHERE  cb.estado <> 2   -- excluye cuentas inactivas
            ORDER BY cb.id_cuenta;

        OPEN cur_balance_cuentas;
        FETCH NEXT FROM cur_balance_cuentas
            INTO @id_cuenta, @nombre_banco, @tipo_cuenta,
                 @saldo_actual, @estado_cuenta, @desc_estado;

        WHILE @@FETCH_STATUS = 0
        BEGIN
            -- calcula el total de ingresos aplicados para esta cuenta
            SELECT @total_ingresos = ISNULL(SUM(monto_ingresado), 0)
            FROM   ingreso
            WHERE  id_cuenta = @id_cuenta
              AND  estado    = 1;   -- solo aplicados

            -- calcula el total de gastos registrados para esta cuenta
            SELECT @total_gastos = ISNULL(SUM(monto), 0)
            FROM   gastos
            WHERE  id_cuenta = @id_cuenta;

            -- cuenta las compras con ingresos pendientes asociados a esta cuenta
            SELECT @compras_pend = COUNT(DISTINCT i.id_compra)
            FROM   ingreso  i
            JOIN   compra   c ON c.id_compra  = i.id_compra
            WHERE  i.id_cuenta = @id_cuenta
              AND  i.estado    = 2    -- ingresos pendientes
              AND  c.estado_pago = 2; -- compras también pendientes

            -- balance contable: lo que entró menos lo que salió
            SET @balance_calc = @total_ingresos - @total_gastos;

            -- discrepancia entre el saldo real y el calculado
            -- una diferencia positiva indica ingresos no registrados como ingreso;
            -- una negativa puede indicar gastos no registrados o ajustes manuales
            SET @discrepancia = @saldo_actual - @balance_calc;

            -- lógica de bloqueo / desbloqueo automático:
            -- si la cuenta está bloqueada (3) pero su saldo real ya recuperó
            -- el umbral crítico (>= 10.000), se reactiva (1)
            -- si la cuenta está activa (1) pero el saldo real cayó bajo el
            -- umbral (< 10.000), se bloquea (3) de forma preventiva
            SET @accion_aplicada = 'Sin cambio';
            SET @nuevo_estado    = @estado_cuenta;

            IF @estado_cuenta = 3 AND @saldo_actual >= 10000.00
            BEGIN
                UPDATE cuenta_bancaria
                SET    estado = 1
                WHERE  id_cuenta = @id_cuenta;

                SET @nuevo_estado    = 1;
                SET @accion_aplicada = 'Reactivada';
                SET @cuentas_reactivadas = @cuentas_reactivadas + 1;
            END
            ELSE IF @estado_cuenta = 1 AND @saldo_actual < 10000.00
            BEGIN
                UPDATE cuenta_bancaria
                SET    estado = 3
                WHERE  id_cuenta = @id_cuenta;

                SET @nuevo_estado    = 3;
                SET @accion_aplicada = 'Bloqueada';
                SET @cuentas_bloqueadas = @cuentas_bloqueadas + 1;
            END;

            -- acumula la fila en la tabla de resultados
            INSERT INTO #balance_cuentas
            VALUES (
                @id_cuenta, @nombre_banco, @tipo_cuenta,
                @saldo_actual, @total_ingresos, @total_gastos,
                @balance_calc, @discrepancia, @compras_pend,
                @desc_estado,
                CASE @nuevo_estado WHEN 1 THEN 'activa'
                                   WHEN 3 THEN 'bloqueada'
                                   ELSE        @desc_estado END,
                @accion_aplicada
            );

            -- acumula totales globales de la joyería
            SET @gran_total_ingresos = @gran_total_ingresos + @total_ingresos;
            SET @gran_total_gastos   = @gran_total_gastos   + @total_gastos;
            SET @saldo_total_real    = @saldo_total_real    + @saldo_actual;
            SET @cuentas_procesadas  = @cuentas_procesadas  + 1;

            FETCH NEXT FROM cur_balance_cuentas
                INTO @id_cuenta, @nombre_banco, @tipo_cuenta,
                     @saldo_actual, @estado_cuenta, @desc_estado;
        END;

        CLOSE     cur_balance_cuentas;
        DEALLOCATE cur_balance_cuentas;

        -- resultado 1: auditoría completa por cuenta
        SELECT *
        FROM   #balance_cuentas
        ORDER BY id_cuenta;

        -- resultado 2: resumen financiero global de soul cr
        SELECT
            @cuentas_procesadas  AS cuentas_auditadas,
            @gran_total_ingresos AS ingresos_totales_aplicados,
            @gran_total_gastos   AS gastos_totales,
            @gran_total_ingresos - @gran_total_gastos
                                 AS balance_neto_calculado,
            @saldo_total_real    AS saldo_real_total,
            @saldo_total_real - (@gran_total_ingresos - @gran_total_gastos)
                                 AS discrepancia_global,
            @cuentas_bloqueadas  AS cuentas_bloqueadas_en_auditoria,
            @cuentas_reactivadas AS cuentas_reactivadas_en_auditoria;

        DROP TABLE #balance_cuentas;

    END TRY
    BEGIN CATCH
        -- limpieza del cursor si quedó abierto por un error
        IF CURSOR_STATUS('local', 'cur_balance_cuentas') >= 0
        BEGIN
            CLOSE     cur_balance_cuentas;
            DEALLOCATE cur_balance_cuentas;
        END;
        IF OBJECT_ID('tempdb..#balance_cuentas') IS NOT NULL
            DROP TABLE #balance_cuentas;
        THROW;
    END CATCH;
END;
GO


-- ============================================================
-- resumen de triggers y cursores implementados:
--
-- TRIGGER 1: trg_after_insert_detalle_compra
--     evento:  AFTER INSERT en detalle_compra
--     tablas:  detalle_compra (base) → compra (actualizada)
--     lógica:  recalcula monto_total en compra sumando todas las
--              líneas del detalle (set-based, un solo UPDATE)
--     valor:   garantiza consistencia del total sin importar la
--              vía de inserción; complementa sp_registrar_venta_completa
--
-- TRIGGER 2: trg_after_insert_ingreso
--     evento:  AFTER INSERT en ingreso
--     tablas:  ingreso (base) → compra, cuenta_bancaria
--     lógica:  estado=2: valida que la compra también esté pendiente
--              estado=1: aplica la compra y acredita saldo en cuenta
--     valor:   cubre inserciones directas de ingresos; no interfiere
--              con sp_confirmar_pago (que hace UPDATE, no INSERT)
--
-- TRIGGER 3: trg_after_insert_gastos
--     evento:  AFTER INSERT en gastos
--     tablas:  gastos (base) → cuenta_bancaria
--     lógica:  si saldo < monto → ROLLBACK (protección último recurso)
--              si saldo - monto < ₡10.000 → bloquea cuenta (estado=3)
--     valor:   protege integridad financiera para inserciones directas;
--              es idempotente con sp_registrar_gasto_y_descontar_saldo
--
-- CURSOR 1: cur_reporte_alertas_stock (en sp_reporte_alertas_stock)
--     recorre:  inventario con cantidad_disponible < cantidad_minima
--     tablas:   inventario, producto, categoria_producto, tipo_material
--     efectos:  cambia inventario.estado a 3 (revision) para productos activos
--     retorna:  detalle de alertas + resumen (totales y costos estimados)
--
-- CURSOR 2: cur_balance_cuentas (en sp_balance_cuentas)
--     recorre:  cuenta_bancaria donde estado ≠ 2 (inactiva)
--     tablas:   cuenta_bancaria, estado_cuenta, ingreso, gastos, compra
--     efectos:  reactiva cuentas bloqueadas con saldo >= ₡10.000
--               bloquea cuentas activas con saldo < ₡10.000
--     retorna:  auditoría por cuenta + resumen financiero global
-- ============================================================