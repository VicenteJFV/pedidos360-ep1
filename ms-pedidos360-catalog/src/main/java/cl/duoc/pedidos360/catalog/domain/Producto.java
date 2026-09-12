package cl.duoc.pedidos360.catalog.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.PrePersist;
import jakarta.persistence.PreUpdate;
import jakarta.persistence.SequenceGenerator;
import jakarta.persistence.Table;
import jakarta.persistence.UniqueConstraint;
import jakarta.persistence.Version;

import java.math.BigDecimal;
import java.time.LocalDateTime;

@Entity
@Table(
        name = "PRODUCTO",
        uniqueConstraints = @UniqueConstraint(name = "UK_PRODUCTO_SKU", columnNames = "SKU")
)
public class Producto {

    @Id
    @GeneratedValue(strategy = GenerationType.SEQUENCE, generator = "productoSeqGen")
    @SequenceGenerator(name = "productoSeqGen", sequenceName = "PRODUCTO_SEQ", allocationSize = 1)
    @Column(name = "ID")
    private Long id;

    @Column(name = "SKU", nullable = false, length = 40)
    private String sku;

    @Column(name = "NOMBRE", nullable = false, length = 150)
    private String nombre;

    @Column(name = "DESCRIPCION", length = 500)
    private String descripcion;

    @Column(name = "PRECIO", nullable = false, precision = 12, scale = 2)
    private BigDecimal precio;

    @Column(name = "STOCK", nullable = false)
    private Integer stock;

    @Column(name = "CATEGORIA", length = 60)
    private String categoria;

    @Column(name = "ACTIVO", nullable = false)
    private Boolean activo;

    /** Bloqueo optimista: evita que dos reservas simultaneas pisen el mismo stock. */
    @Version
    @Column(name = "VERSION")
    private Long version;

    @Column(name = "FECHA_CREACION", nullable = false)
    private LocalDateTime fechaCreacion;

    @Column(name = "FECHA_ACTUALIZACION")
    private LocalDateTime fechaActualizacion;

    protected Producto() {
        // requerido por JPA
    }

    public Producto(String sku, String nombre, String descripcion, BigDecimal precio,
                    Integer stock, String categoria) {
        this.sku = sku;
        this.nombre = nombre;
        this.descripcion = descripcion;
        this.precio = precio;
        this.stock = stock;
        this.categoria = categoria;
        this.activo = Boolean.TRUE;
    }

    @PrePersist
    void alCrear() {
        this.fechaCreacion = LocalDateTime.now();
        this.fechaActualizacion = this.fechaCreacion;
        if (this.activo == null) {
            this.activo = Boolean.TRUE;
        }
        if (this.stock == null) {
            this.stock = 0;
        }
    }

    @PreUpdate
    void alActualizar() {
        this.fechaActualizacion = LocalDateTime.now();
    }

    /** Descuenta stock validando disponibilidad. Devuelve false si no alcanza. */
    public boolean descontarStock(int cantidad) {
        if (cantidad <= 0) {
            throw new IllegalArgumentException("La cantidad a descontar debe ser mayor a cero");
        }
        if (this.stock < cantidad) {
            return false;
        }
        this.stock = this.stock - cantidad;
        return true;
    }

    /** Devuelve stock al inventario (cancelacion de un pedido ya aceptado). */
    public void reponerStock(int cantidad) {
        if (cantidad <= 0) {
            throw new IllegalArgumentException("La cantidad a reponer debe ser mayor a cero");
        }
        this.stock = this.stock + cantidad;
    }

    public boolean estaDisponible(int cantidad) {
        return Boolean.TRUE.equals(this.activo) && this.stock != null && this.stock >= cantidad;
    }

    public Long getId() {
        return id;
    }

    public String getSku() {
        return sku;
    }

    public void setSku(String sku) {
        this.sku = sku;
    }

    public String getNombre() {
        return nombre;
    }

    public void setNombre(String nombre) {
        this.nombre = nombre;
    }

    public String getDescripcion() {
        return descripcion;
    }

    public void setDescripcion(String descripcion) {
        this.descripcion = descripcion;
    }

    public BigDecimal getPrecio() {
        return precio;
    }

    public void setPrecio(BigDecimal precio) {
        this.precio = precio;
    }

    public Integer getStock() {
        return stock;
    }

    public void setStock(Integer stock) {
        this.stock = stock;
    }

    public String getCategoria() {
        return categoria;
    }

    public void setCategoria(String categoria) {
        this.categoria = categoria;
    }

    public Boolean getActivo() {
        return activo;
    }

    public void setActivo(Boolean activo) {
        this.activo = activo;
    }

    public Long getVersion() {
        return version;
    }

    public LocalDateTime getFechaCreacion() {
        return fechaCreacion;
    }

    public LocalDateTime getFechaActualizacion() {
        return fechaActualizacion;
    }
}
