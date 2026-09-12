package cl.duoc.pedidos360.catalog.repository;

import cl.duoc.pedidos360.catalog.domain.Producto;
import jakarta.persistence.LockModeType;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.List;
import java.util.Optional;

public interface ProductoRepository extends JpaRepository<Producto, Long> {

    Optional<Producto> findBySku(String sku);

    boolean existsBySku(String sku);

    List<Producto> findByActivoTrueOrderByNombreAsc();

    List<Producto> findByCategoriaIgnoreCaseOrderByNombreAsc(String categoria);

    /**
     * Bloqueo pesimista para la operacion de reserva de stock. Serializa las reservas
     * concurrentes sobre el mismo producto y evita vender stock que ya no existe.
     */
    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("select p from Producto p where p.id = :id")
    Optional<Producto> findByIdParaActualizar(@Param("id") Long id);
}
