package cl.duoc.pedidos360.orders.domain;

import cl.duoc.pedidos360.orders.exception.TransicionInvalidaException;
import jakarta.persistence.CascadeType;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.FetchType;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.OneToMany;
import jakarta.persistence.PrePersist;
import jakarta.persistence.PreUpdate;
import jakarta.persistence.SequenceGenerator;
import jakarta.persistence.Table;
import jakarta.persistence.UniqueConstraint;
import jakarta.persistence.Version;

import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;

@Entity
@Table(
        name = "PEDIDO",
        uniqueConstraints = @UniqueConstraint(name = "UK_PEDIDO_CODIGO", columnNames = "CODIGO")
)
public class Pedido {

    @Id
    @GeneratedValue(strategy = GenerationType.SEQUENCE, generator = "pedidoSeqGen")
    @SequenceGenerator(name = "pedidoSeqGen", sequenceName = "PEDIDO_SEQ", allocationSize = 1)
    @Column(name = "ID")
    private Long id;

    @Column(name = "CODIGO", nullable = false, length = 40)
    private String codigo;

    @Column(name = "CLIENTE_EMAIL", nullable = false, length = 180)
    private String clienteEmail;

    @Column(name = "CLIENTE_NOMBRE", length = 150)
    private String clienteNombre;

    @Enumerated(EnumType.STRING)
    @Column(name = "ESTADO", nullable = false, length = 20)
    private EstadoPedido estado;

    @Column(name = "TOTAL", nullable = false, precision = 14, scale = 2)
    private BigDecimal total;

    @Column(name = "OBSERVACION", length = 500)
    private String observacion;

    @Column(name = "DIRECCION_ENTREGA", length = 300)
    private String direccionEntrega;

    @Version
    @Column(name = "VERSION")
    private Long version;

    @Column(name = "FECHA_CREACION", nullable = false)
    private LocalDateTime fechaCreacion;

    @Column(name = "FECHA_ACTUALIZACION")
    private LocalDateTime fechaActualizacion;

    @OneToMany(mappedBy = "pedido", cascade = CascadeType.ALL, orphanRemoval = true, fetch = FetchType.LAZY)
    private List<PedidoItem> items = new ArrayList<>();

    protected Pedido() {
        // requerido por JPA
    }

    public Pedido(String codigo, String clienteEmail, String clienteNombre, String direccionEntrega) {
        this.codigo = codigo;
        this.clienteEmail = clienteEmail;
        this.clienteNombre = clienteNombre;
        this.direccionEntrega = direccionEntrega;
        this.estado = EstadoPedido.CREADO;
        this.total = BigDecimal.ZERO;
    }

    @PrePersist
    void alCrear() {
        this.fechaCreacion = LocalDateTime.now();
        this.fechaActualizacion = this.fechaCreacion;
        if (this.estado == null) {
            this.estado = EstadoPedido.CREADO;
        }
    }

    @PreUpdate
    void alActualizar() {
        this.fechaActualizacion = LocalDateTime.now();
    }

    public void agregarItem(PedidoItem item) {
        item.asociarA(this);
        this.items.add(item);
        recalcularTotal();
    }

    private void recalcularTotal() {
        this.total = this.items.stream()
                .map(PedidoItem::getSubtotal)
                .reduce(BigDecimal.ZERO, BigDecimal::add);
    }

    /**
     * Unico punto por donde cambia el estado. Si la transicion no esta permitida
     * por la maquina de estados, lanza excepcion y el pedido no se toca.
     */
    public void cambiarEstado(EstadoPedido destino) {
        if (!this.estado.puedeTransicionarA(destino)) {
            throw new TransicionInvalidaException(this.codigo, this.estado, destino);
        }
        this.estado = destino;
    }

    public boolean tieneStockReservado() {
        return this.estado.tieneStockReservado();
    }

    public Long getId() {
        return id;
    }

    public String getCodigo() {
        return codigo;
    }

    public String getClienteEmail() {
        return clienteEmail;
    }

    public String getClienteNombre() {
        return clienteNombre;
    }

    public EstadoPedido getEstado() {
        return estado;
    }

    public BigDecimal getTotal() {
        return total;
    }

    public String getObservacion() {
        return observacion;
    }

    public void setObservacion(String observacion) {
        this.observacion = observacion;
    }

    public String getDireccionEntrega() {
        return direccionEntrega;
    }

    public void setDireccionEntrega(String direccionEntrega) {
        this.direccionEntrega = direccionEntrega;
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

    public List<PedidoItem> getItems() {
        return Collections.unmodifiableList(items);
    }
}
