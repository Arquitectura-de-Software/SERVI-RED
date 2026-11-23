import { ComponentFixture, TestBed } from '@angular/core/testing';
import { provideRouter } from '@angular/router';
import { Inicio } from './inicio';

describe('Inicio', () => {
  let fixture: ComponentFixture<Inicio>;

  beforeEach(async () => {
    await TestBed.configureTestingModule({
      imports: [Inicio],
      providers: [provideRouter([])],
    }).compileComponents();
    fixture = TestBed.createComponent(Inicio);
    fixture.detectChanges();
  });

  it('dirige al login de operador y al portal público', () => {
    const links = Array.from(fixture.nativeElement.querySelectorAll('a')) as HTMLAnchorElement[];

    expect(links.map((link) => link.getAttribute('href'))).toEqual(['/login', '/datos-abiertos']);
  });
});
