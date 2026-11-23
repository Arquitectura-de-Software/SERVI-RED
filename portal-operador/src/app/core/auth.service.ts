import { Injectable, computed, inject, signal } from '@angular/core';
import { Session } from '@supabase/supabase-js';
import { SupabaseService } from './supabase.service';
import { Perfil, Rol } from './tipos';
import { exigir } from './errores';

/** Roles que entran al portal. El ciudadano usa la app móvil. */
export const ROLES_PORTAL: Rol[] = ['operador', 'regulador', 'admin'];

@Injectable({ providedIn: 'root' })
export class AuthService {
  private readonly sb = inject(SupabaseService).client;

  readonly sesion = signal<Session | null>(null);
  readonly perfil = signal<Perfil | null>(null);
  readonly rol = computed(() => this.perfil()?.rol ?? null);
  readonly puedeGestionar = computed(() => this.rol() === 'operador' || this.rol() === 'admin');
  readonly esOperador = computed(() => this.rol() === 'operador');

  private listo: Promise<void> | null = null;

  constructor() {
    this.sb.auth.onAuthStateChange((evento, sesion) => {
      this.sesion.set(sesion);
      if (evento === 'SIGNED_OUT') {
        this.perfil.set(null);
      }
    });
  }

  /** Carga la sesión guardada y el perfil una sola vez. */
  iniciar(): Promise<void> {
    this.listo ??= (async () => {
      const { data } = await this.sb.auth.getSession();
      this.sesion.set(data.session);
      if (data.session) {
        try {
          await this.cargarPerfil(data.session.user.id);
        } catch {
          await this.sb.auth.signOut();
          this.sesion.set(null);
        }
      }
    })();
    return this.listo;
  }

  async entrar(email: string, password: string): Promise<Perfil> {
    const { data, error } = await this.sb.auth.signInWithPassword({ email, password });
    if (error || !data.session) {
      throw { tipo: 'sesion', mensaje: 'Correo o contraseña incorrectos.' };
    }
    this.sesion.set(data.session);
    const perfil = await this.cargarPerfil(data.user.id);
    if (!perfil.activo || !ROLES_PORTAL.includes(perfil.rol)) {
      await this.salir();
      throw { tipo: 'permiso', mensaje: 'Esta cuenta no tiene acceso al portal del operador.' };
    }
    this.listo = Promise.resolve();
    return perfil;
  }

  async salir(): Promise<void> {
    await this.sb.auth.signOut();
    this.sesion.set(null);
    this.perfil.set(null);
    this.listo = Promise.resolve();
  }

  /** El rol sale de `perfil` (RLS: cada quien lee el suyo), nunca del cliente. */
  private async cargarPerfil(uid: string): Promise<Perfil> {
    const p = exigir(
      await this.sb.from('perfil').select('id, rol, activo').eq('id', uid).single<{ id: string; rol: Rol; activo: boolean }>(),
    );
    let empresaId: string | null = null;
    let nombre: string | null = null;
    if (p.rol === 'operador') {
      const o = exigir(
        await this.sb
          .from('operador')
          .select('empresa_id, nombre_completo')
          .eq('id', uid)
          .single<{ empresa_id: string; nombre_completo: string }>(),
      );
      empresaId = o.empresa_id;
      nombre = o.nombre_completo;
    }
    const perfil: Perfil = { id: p.id, rol: p.rol, activo: p.activo, empresaId, nombre };
    this.perfil.set(perfil);
    return perfil;
  }
}
