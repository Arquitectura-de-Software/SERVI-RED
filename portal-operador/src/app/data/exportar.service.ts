import { Injectable, inject } from '@angular/core';
import { SupabaseService } from '../core/supabase.service';
import { exigir } from '../core/errores';

export interface FiltrosExportacion {
  desde: string; // yyyy-mm-dd (hora de Colombia)
  hasta: string;
  servicioId: number | null;
  empresaId: string | null;
}

@Injectable({ providedIn: 'root' })
export class ExportarService {
  private readonly sb = inject(SupabaseService).client;

  /**
   * exportar_incidentes por POST con `Accept: text/csv`: PostgREST devuelve el CSV
   * directamente. La base fuerza la empresa del operador y registra la exportación.
   */
  async csv(f: FiltrosExportacion): Promise<string> {
    const r = await this.sb
      .rpc('exportar_incidentes', {
        p_desde: f.desde,
        p_hasta: f.hasta,
        p_servicio_id: f.servicioId,
        p_empresa_id: f.empresaId,
      })
      .csv();
    return exigir(r) as unknown as string;
  }
}
