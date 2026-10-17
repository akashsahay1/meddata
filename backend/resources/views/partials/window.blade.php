{{-- A real app screenshot in a desktop app window. $src, $alt, optional $class, $eager. --}}
<div class="window {{ $class ?? '' }}">
  <div class="bar"><span class="bar-title"><img src="/images/favicon.svg" alt="" width="14" height="14">Medikabiz</span><span class="bar-ctl" aria-hidden="true"><i><svg viewBox="0 0 10 10"><path d="M0 5.5h10"/></svg></i><i><svg viewBox="0 0 10 10"><rect x=".5" y=".5" width="9" height="9" rx="1"/></svg></i><i><svg viewBox="0 0 10 10"><path d="M.5.5l9 9M9.5.5l-9 9"/></svg></i></span></div>
  <img src="{{ $src }}?v={{ filemtime(public_path($src)) }}" width="1600" height="1000" @unless($eager ?? false) loading="lazy" @endunless alt="{{ $alt }}">
</div>
