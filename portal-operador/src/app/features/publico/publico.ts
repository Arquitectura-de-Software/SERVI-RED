import { Component, OnInit, inject, signal } from '@angular/core';
import { CommonModule } from '@angular/common';
import { SupabaseService } from '../../core/supabase.service';
@Component({selector:'app-p5-publico',standalone:true,imports:[CommonModule],template:`
<main style="max-width:1100px;margin:auto;padding:2rem;font-family:system-ui">
<h1>Datos abiertos | SERVI-RED</h1><p>Indicadores agregados de continuidad por municipio, servicio y mes. No se publican datos personales.</p>
<p *ngIf="error()" role="alert">{{error()}}</p>
<p *ngIf="loading()">Cargando indicadores…</p>
<button type="button" (click)="csv()">Descargar CSV</button>
<button type="button" (click)="geojson()">Descargar GeoJSON (atributos, sin geometrías)</button>
<div style="overflow:auto"><table style="border-collapse:collapse;width:100%;margin-top:1rem"><thead><tr><th>Mes</th><th>Servicio</th><th>Municipio</th><th>Departamento</th><th>Incidentes</th><th>Horas promedio</th><th>Minutos restablecimiento</th><th>Reportes</th><th>Llenado %</th></tr></thead>
<tbody><tr *ngFor="let r of rows()"><td>{{r.mes}}</td><td>{{r.servicio}}</td><td>{{r.municipio}}</td><td>{{r.departamento}}</td><td>{{r.incidentes}}</td><td>{{r.horas_promedio_interrupcion}}</td><td>{{r.minutos_promedio_restauracion}}</td><td>{{r.reportes}}</td><td>{{r.porcentaje_llenado}}</td></tr></tbody></table></div>
<p>Para representar polígonos geográficos se requiere una capa GeoJSON oficial del DANE. No se generan geometrías inventadas.</p>
</main>`,styles:[`th,td{border:1px solid #ddd;padding:.55rem;text-align:left}th{background:#f2f5f8}button{margin-right:.7rem;padding:.7rem;cursor:pointer}`]})
export class Publico implements OnInit {
 private sb=inject(SupabaseService); rows=signal<any[]>([]);error=signal('');loading=signal(true);
 async ngOnInit(){try{const {data,error}=await this.sb.client.rpc('p5_indicadores_publicos');if(error)throw error;this.rows.set(data||[])}catch(e:any){this.error.set('No se pudieron cargar los indicadores: '+e.message)}finally{this.loading.set(false)}}
 private save(data:string,name:string,type:string){const u=URL.createObjectURL(new Blob([data],{type}));const a=document.createElement('a');a.href=u;a.download=name;a.click();URL.revokeObjectURL(u)}
 csv(){const keys=['mes','servicio','municipio','departamento','incidentes','horas_promedio_interrupcion','minutos_promedio_restauracion','reportes','porcentaje_llenado'];const esc=(v:any)=>'"'+String(v??'').replace(/"/g,'""')+'"';this.save([keys.join(','),...this.rows().map(r=>keys.map(k=>esc(r[k])).join(','))].join('\n'),'servired_indicadores.csv','text/csv;charset=utf-8')}
 geojson(){this.save(JSON.stringify({type:'FeatureCollection',features:this.rows().map(r=>({type:'Feature',geometry:null,properties:r}))},null,2),'servired_indicadores.geojson','application/geo+json')}
}
