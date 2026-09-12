package cl.duoc.pedidos360.orders.repository;

import cl.duoc.pedidos360.orders.domain.EstadoPedido;
import cl.duoc.pedidos360.orders.domain.Pedido;
import org.springframework.data.jpa.repository.EntityGraph;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.List;
import java.util.Optional;

public interface PedidoRepository extends JpaRepository<Pedido, Long> {

    /**
     * EntityGraph para traer los items en la misma consulta. Sin esto, con
     * open-in-view=false y fetch LAZY, el mapeo a DTO dispararia N+1 consultas.
     */
    @EntityGraph(attributePaths = "items")
    Optional<Pedido> findWithItemsById(Long id);

    @EntityGraph(attributePaths = "items")
    Optional<Pedido> findWithItemsByCodigo(String codigo);

    @EntityGraph(attributePaths = "items")
    @Query("""
            select distinct p from Pedido p
            where (:clienteEmail is null or lower(p.clienteEmail) = lower(:clienteEmail))
              and (:estado is null or p.estado = :estado)
            order by p.fechaCreacion desc
            """)
    List<Pedido> buscar(@Param("clienteEmail") String clienteEmail,
                        @Param("estado") EstadoPedido estado);

    boolean existsByCodigo(String codigo);
}
