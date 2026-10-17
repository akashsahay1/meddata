{{-- A real app screenshot in an Android phone frame. $src, $alt, $tone (status bar icons: light|dark), optional $class, $eager. --}}
<div class="device {{ $class ?? '' }}"><div class="frame"><div class="screen">
  <div class="status {{ $tone }}"><span>9:41</span><span class="sicons"><svg viewBox="0 0 18 12"><path d="M1 11h2V8H1zm4 0h2V6H5zm4 0h2V4H9zm4 0h2V1h-2z"/></svg><svg viewBox="0 0 16 12"><path d="M8 11.5 1 4.3a10 10 0 0 1 14 0zm0-2.8 3.4-3.5a5 5 0 0 0-6.8 0z" fill-opacity=".35"/><path d="M8 11.5 4.6 8.1a4.8 4.8 0 0 1 6.8 0z"/></svg><svg viewBox="0 0 26 12"><rect x=".5" y=".5" width="21" height="11" rx="3" fill="none" stroke="currentColor" stroke-opacity=".5"/><rect x="2" y="2" width="16" height="8" rx="1.8"/><rect x="23" y="4" width="2" height="4" rx="1" fill-opacity=".5"/></svg></span></div>
  <span class="camera"></span>
  <img src="{{ $src }}" width="780" height="1688" @unless($eager ?? false) loading="lazy" @endunless alt="{{ $alt }}">
</div></div></div>
