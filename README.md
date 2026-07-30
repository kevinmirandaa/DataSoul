<div align="center">

# <img src="https://api.iconify.design/mdi:database-outline.svg?color=%23028ECC" width="28" valign="middle"> DataSoul

**Base de datos relacional para Soul CR — tienda de joyería y accesorios artesanales**

<img src="https://img.shields.io/badge/-SQL%20Server-383635?style=flat-square&logo=microsoftsqlserver&logoColor=CC2927" />
<img src="https://img.shields.io/badge/-T--SQL-028ECC?style=flat-square" />
<img src="https://img.shields.io/badge/-Node.js%20%2F%20Express-EC5E1E?style=flat-square&logo=node.js&logoColor=white" />
<img src="https://img.shields.io/badge/-4FN%20Normalizado-FBBF02?style=flat-square" />

<br><br>

<sub>Proyecto desarrollado para el curso de <strong>Bases de Datos I</strong> — Tecnológico de Costa Rica</sub>

</div>

---

## <img src="https://api.iconify.design/mdi:file-document-outline.svg?color=%23028ECC" width="20" valign="middle"> Descripción

**Soul CR** es una tienda en línea de joyería y accesorios artesanales ubicada en Pital, San Carlos, Costa Rica, que antes de este proyecto administraba su información de forma manual y dispersa. **DataSoul** centraliza esa operación en una base de datos relacional formal, diseñada en **Microsoft SQL Server** a partir del modelo Entidad-Relación y el modelo relacional normalizado hasta la **Cuarta Forma Normal (4FN)**.

El sistema cubre cuatro módulos: gestión de inventario y productos, registro de ventas y clientes, administración de finanzas, y visualización de catálogo. Este repositorio contiene el script completo de la base de datos junto con un prototipo de aplicación web que consume su lógica.

## <img src="https://api.iconify.design/mdi:table-large.svg?color=%23EC5E1E" width="20" valign="middle"> Modelo de datos

24 tablas organizadas en seis grupos funcionales:

| Grupo | Contenido |
|---|---|
| Catálogo (FN4) | 7 tablas de enumeraciones de estado (cliente, pago, cuenta, inventario, etc.) |
| Geografía | 3 tablas para la estructura territorial de Costa Rica (provincia, cantón, distrito) |
| Clientes | 4 tablas, con atributos multivaluados (email, teléfono, dirección) separados en tablas propias |
| Productos e inventario | 4 tablas |
| Ventas y pagos | 3 tablas |
| Finanzas | 3 tablas |

Dos tablas usan **clave primaria compuesta**: `detalle_compra` (entidad débil, PK `id_compra + id_producto`) y `direccion` (PK `id_cliente + id_distrito`).

## <img src="https://api.iconify.design/mdi:cog-outline.svg?color=%23FBBF02" width="20" valign="middle"> Componentes implementados

| Componente | Cantidad | Detalle |
|---|---|---|
| Tablas | 24 | 24 PKs, 26 FKs, 23 restricciones CHECK, 4 UNIQUE, ~75 columnas NOT NULL |
| Tipos de datos personalizados | 5 | `tipo_email`, `tipo_telefono`, `tipo_monto`, `tipo_nombre_persona`, `tipo_codigo_producto` |
| Procedimientos CRUD | 96 | 4 por tabla (`sp_insertar_X`, `sp_actualizar_X`, `sp_eliminar_X`, `sp_consultar_X`) |
| Procedimientos transaccionales | 5 | Venta completa, confirmación de pago, registro de gasto, devolución, transferencia entre cuentas |
| Procedimientos con cursor | 2 | Reporte de alertas de stock, auditoría y balance de cuentas |
| Vistas | 3 | Alertas de inventario, historial de ventas, estado financiero |
| Disparadores | 3 | Sincronización de totales, aplicación de ingresos, control de saldo |
| Índices adicionales | 3 | Sobre `compra`, `detalle_compra` y `ingreso`, orientados a las consultas más frecuentes |
| Valores por defecto | 5 | Estado inicial de cliente, fechas automáticas, estado de compra pendiente |
| Datos de prueba | 134 registros | Datos reales: provincias/cantones/distritos de Costa Rica, productos con precios en colones |

## <img src="https://api.iconify.design/mdi:swap-horizontal.svg?color=%23028ECC" width="20" valign="middle"> Procedimientos transaccionales

Los cinco procedimientos que garantizan atomicidad (propiedades **ACID**) sobre operaciones que afectan múltiples tablas:

- **`sp_registrar_venta_completa`** — valida stock, crea la compra, descuenta inventario, calcula el total y registra el pago e ingreso, todo en una sola transacción.
- **`sp_confirmar_pago`** — valida y aplica un pago pendiente, acredita el monto en la cuenta correspondiente.
- **`sp_registrar_gasto_y_descontar_saldo`** — descuenta saldo y bloquea automáticamente la cuenta si cae bajo el umbral crítico (₡10.000).
- **`sp_devolver_compra`** — revierte una compra aplicada: restaura inventario con un cursor interno, reactiva productos agotados y descuenta el ingreso.
- **`sp_transferir_entre_cuentas`** — mueve saldo entre dos cuentas activas en una sola transacción atómica.

## <img src="https://api.iconify.design/mdi:chart-line.svg?color=%23EC5E1E" width="20" valign="middle"> Consultas avanzadas

Cinco consultas con JOIN múltiple, funciones de ventana y CTEs: top de productos más vendidos, productos con stock bajo mínimo, historial de cliente con ranking (`RANK() OVER`), resumen financiero por cuenta, y antigüedad de cartera de deudas pendientes con clasificación por tramos de mora.

## <img src="https://api.iconify.design/mdi:monitor-dashboard.svg?color=%23FBBF02" width="20" valign="middle"> Prototipo de aplicación web

Arquitectura cliente-servidor: **frontend** en HTML, CSS y JavaScript, **backend** con **Node.js + Express**, conectado directamente a SQL Server y consumiendo los procedimientos almacenados, vistas y cursores del script.

- **Clientes** — registro, edición e historial de compras.
- **Inventario y productos** — catálogo, stock y alertas de bajo inventario (`vw_inventario_alertas`, `cur_reporte_alertas_stock`).
- **Finanzas** — estado de cuentas (`vw_estado_financiero`), registro de gastos, confirmación de pagos, transferencias y auditoría (`cur_balance_cuentas`).

## <img src="https://api.iconify.design/mdi:tools.svg?color=%23028ECC" width="20" valign="middle"> Tecnologías

- **Microsoft SQL Server** — motor de base de datos
- **T-SQL** — procedimientos, vistas, disparadores, cursores
- **Node.js + Express** — backend / API REST
- **HTML, CSS, JavaScript** — frontend del prototipo

## <img src="https://api.iconify.design/mdi:folder-outline.svg?color=%23EC5E1E" width="20" valign="middle"> Estructura del proyecto

```
DataSoul/
└── database/
    └── DataSoul.sql   # Script completo: BD, tipos, tablas, procedimientos,
                        # vistas, disparadores, cursores y datos de prueba
```

## <img src="https://api.iconify.design/mdi:rocket-launch-outline.svg?color=%23FBBF02" width="20" valign="middle"> Cómo ejecutarlo

1. Abrir **SQL Server Management Studio** (o Azure Data Studio).
2. Conectarse a una instancia de SQL Server.
3. Ejecutar `database/DataSoul.sql` completo. El script crea la base de datos `DataSoul` desde cero (incluye limpieza previa), define tipos, tablas, procedimientos, vistas, disparadores, cursores e inserta los datos de prueba.

## <img src="https://api.iconify.design/mdi:book-open-outline.svg?color=%23028ECC" width="20" valign="middle"> Referencias

- A. Silberschatz, H. F. Korth y S. Sudarshan, *Fundamentos de Bases de Datos*, 4.ª ed. Madrid, España: McGraw-Hill, 2002.
- Microsoft Corporation, "Bases de Datos", *Microsoft Learn*.

## <img src="https://api.iconify.design/mdi:account-multiple-outline.svg?color=%23EC5E1E" width="20" valign="middle"> Equipo

Proyecto desarrollado en equipo para el curso Bases de Datos.

**Kevin Miranda Méndez**
