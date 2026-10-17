{{-- A real app screenshot in a desktop app window. $src, $alt, optional $class, $eager. --}}
<div class="window {{ $class ?? '' }}">
  <div class="bar"><span class="bar-title"><img src="/images/favicon.svg" alt="" width="14" height="14">Medikabiz</span><span class="bar-ctl" aria-hidden="true"><i>–</i><i>▢</i><i>✕</i></span></div>
  <img src="{{ $src }}" width="1600" height="1000" @unless($eager ?? false) loading="lazy" @endunless alt="{{ $alt }}">
</div>
