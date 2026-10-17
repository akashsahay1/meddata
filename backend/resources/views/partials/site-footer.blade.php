<footer class="site-foot">
  <div class="wrap">
    <div class="foot-grid">
      <div class="foot-brand">
        <img src="/images/medikabiz_logo_web.png" alt="Medikabiz" width="137" height="36">
        <p>Pharmacy management, made simpler. A {{ config('legal.company') }} initiative.</p>
      </div>
      <nav aria-labelledby="foot-product">
        <h2 id="foot-product">Product</h2>
        <ul>
          <li><a href="/#features">Features</a></li>
          <li><a href="/#pricing">Pricing</a></li>
          <li><a href="/#download">Download</a></li>
          <li><a href="/#faq">Questions</a></li>
        </ul>
      </nav>
      <nav aria-labelledby="foot-legal">
        <h2 id="foot-legal">Legal</h2>
        <ul>
          <li><a href="/privacy-policy">Privacy Policy</a></li>
          <li><a href="/terms">Terms of Service</a></li>
          <li><a href="/refund-policy">Refund &amp; Cancellation</a></li>
          <li><a href="/delivery-policy">Delivery Policy</a></li>
          <li><a href="/cookie-policy">Cookie Policy</a></li>
          <li><a href="/disclaimer">Disclaimer</a></li>
        </ul>
      </nav>
      <div>
        <h2>Contact</h2>
        <ul>
          <li><a href="/contact">Contact us</a></li>
          <li><a href="https://wa.me/{{ config('legal.whatsapp') }}">WhatsApp {{ config('legal.phone') }}</a></li>
          <li><a href="mailto:{{ config('legal.email') }}">{{ config('legal.email') }}</a></li>
        </ul>
      </div>
    </div>
    <div class="foot-legal">
      <span>© {{ date('Y') }} {{ config('legal.company') }}. All rights reserved.</span>
      <span>Medikabiz is a product of {{ config('legal.company') }}, a Section 8 company.</span>
    </div>
  </div>
</footer>
