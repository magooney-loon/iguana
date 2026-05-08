// Hero canvas shader
(function () {
  var canvas = document.getElementById("hero-canvas");
  if (!canvas) return;

  var gl =
    canvas.getContext("webgl") || canvas.getContext("experimental-webgl");
  if (!gl) return;

  var VERT = `
attribute vec2 a_pos;
void main() { gl_Position = vec4(a_pos, 0.0, 1.0); }`;

  var FRAG = `
precision mediump float;
uniform float u_t;
uniform vec2  u_res;
#define TAU 6.2831853

void main() {
    vec2  uv  = gl_FragCoord.xy / u_res;
    uv.y      = 1.0 - uv.y;
    float asp = u_res.x / u_res.y;
    float t   = u_t;
    vec2  p   = (uv - 0.5) * vec2(asp, 1.0);

    // Cheap domain warp — layered trig, no noise needed
    float wt  = t * 0.10;
    vec2  wp  = p + vec2(
        sin(p.y * 2.8 + wt * 0.9) * 0.12 + sin(p.x * 1.5 + wt * 1.3) * 0.08,
        cos(p.x * 2.4 + wt * 0.7) * 0.12 + cos(p.y * 1.9 + wt * 1.1) * 0.08
    );
    vec2  wuv = wp / vec2(asp, 1.0) + 0.5;

    // Animated dark-green conic base (in warped space)
    float ang = fract(atan(wp.y, wp.x) / TAU + 0.5 + t * 0.07);
    float seg = ang * 4.0;
    float sf  = fract(seg);
    vec3  base;
    if      (seg < 1.0) base = mix(vec3(0.04,0.28,0.14), vec3(0.13,0.44,0.21), sf);
    else if (seg < 2.0) base = mix(vec3(0.13,0.44,0.21), vec3(0.02,0.10,0.05), sf);
    else if (seg < 3.0) base = mix(vec3(0.02,0.10,0.05), vec3(0.20,0.56,0.32), sf);
    else                base = mix(vec3(0.20,0.56,0.32), vec3(0.04,0.28,0.14), sf);
    base *= max(0.0, 1.6 - length(wp) * 0.65);

    // Morphing blob colors
    vec3 bc1 = mix(vec3(0.96,0.73,0.26), vec3(1.00,0.42,0.05), sin(t*0.15     )*0.5+0.5);
    vec3 bc2 = mix(vec3(0.22,1.00,0.48), vec3(0.05,0.85,0.92), sin(t*0.12+2.10)*0.5+0.5);
    vec3 bc3 = mix(vec3(0.90,0.42,0.14), vec3(0.92,0.08,0.55), sin(t*0.18+4.20)*0.5+0.5);

    // Large drifting blobs
    vec2 b1 = vec2(0.28 + sin(t*0.23)*0.20, 0.52 + cos(t*0.29)*0.14);
    vec2 b2 = vec2(0.74 + cos(t*0.19)*0.18, 0.58 + sin(t*0.25)*0.16);
    vec2 b3 = vec2(0.56 + sin(t*0.17)*0.17, 0.28 + cos(t*0.21)*0.15);

    float r1 = length((wuv - b1) * vec2(asp, 1.0));
    float r2 = length((wuv - b2) * vec2(asp, 1.0));
    float r3 = length((wuv - b3) * vec2(asp, 1.0));

    float g1 = exp(-r1*r1 * 2.2) * (0.88 + 0.10*sin(t*0.80));
    float g2 = exp(-r2*r2 * 1.8) * (0.88 + 0.10*cos(t*0.65));
    float g3 = exp(-r3*r3 * 2.6) * (0.78 + 0.10*sin(t*1.00));

    vec3 col = base;
    col = 1.0 - (1.0 - col) * (1.0 - bc1 * g1);
    col = 1.0 - (1.0 - col) * (1.0 - bc2 * g2);
    col = 1.0 - (1.0 - col) * (1.0 - bc3 * g3);

    // Warped ripple rings — angular waves distort the radius so rings
    // look like pulsing, wobbly organic ripples instead of perfect circles
    vec2  rv   = (uv - vec2(0.5, 0.55)) * vec2(asp, 1.0);
    float rd   = length(rv);
    float rang = atan(rv.y, rv.x);
    float rdw  = rd
               + sin(rang * 4.0 + t * 0.9)  * 0.045
               + sin(rang * 7.0 - t * 1.4)  * 0.022
               + sin(rang * 2.0 + t * 0.5)  * 0.030;
    float ring = pow(sin(rdw*(u_res.y/22.0)*TAU - t*1.5)*0.5+0.5, 5.0)
                 * 0.28 * smoothstep(1.05, 0.0, rd) * smoothstep(0.0, 0.04, rd);
    vec3  rc   = mix(vec3(0.30,0.85,0.45), vec3(0.90,0.65,0.10), smoothstep(0.0,0.7,rd));
    col = 1.0 - (1.0 - col) * (1.0 - rc * ring);

    // Vignette
    float vig = smoothstep(0.85, 0.20, length(p * vec2(0.75, 1.0)));
    col *= vig;

    // Tonemap + saturation + contrast
    col = col / (col + vec3(0.65));
    float lm = dot(col, vec3(0.299, 0.587, 0.114));
    col = mix(vec3(lm), col, 1.55);
    col = (col - 0.5) * 1.08 + 0.5;
    gl_FragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}`;

  function mkShader(type, src) {
    var sh = gl.createShader(type);
    gl.shaderSource(sh, src);
    gl.compileShader(sh);
    if (!gl.getShaderParameter(sh, gl.COMPILE_STATUS)) {
      console.error("shader:", gl.getShaderInfoLog(sh));
      return null;
    }
    return sh;
  }

  var vs = mkShader(gl.VERTEX_SHADER, VERT);
  var fs = mkShader(gl.FRAGMENT_SHADER, FRAG);
  if (!vs || !fs) return;

  var prog = gl.createProgram();
  gl.attachShader(prog, vs);
  gl.attachShader(prog, fs);
  gl.linkProgram(prog);
  if (!gl.getProgramParameter(prog, gl.LINK_STATUS)) {
    console.error("link:", gl.getProgramInfoLog(prog));
    return;
  }
  gl.useProgram(prog);

  var buf = gl.createBuffer();
  gl.bindBuffer(gl.ARRAY_BUFFER, buf);
  gl.bufferData(
    gl.ARRAY_BUFFER,
    new Float32Array([-1, -1, 1, -1, -1, 1, 1, 1]),
    gl.STATIC_DRAW,
  );
  var aPos = gl.getAttribLocation(prog, "a_pos");
  gl.enableVertexAttribArray(aPos);
  gl.vertexAttribPointer(aPos, 2, gl.FLOAT, false, 0, 0);

  var uT = gl.getUniformLocation(prog, "u_t");
  var uRes = gl.getUniformLocation(prog, "u_res");
  var dpr = Math.min(window.devicePixelRatio || 1, 1.5);
  var start = performance.now();
  var raf;

  function resize() {
    var w = (canvas.clientWidth * dpr) | 0;
    var h = (canvas.clientHeight * dpr) | 0;
    if (canvas.width !== w || canvas.height !== h) {
      canvas.width = w;
      canvas.height = h;
      gl.viewport(0, 0, w, h);
    }
    gl.uniform2f(uRes, w || 1, h || 1);
  }

  new ResizeObserver(resize).observe(canvas);
  resize();

  function draw() {
    gl.uniform1f(uT, (performance.now() - start) * 0.001);
    gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4);
    raf = requestAnimationFrame(draw);
  }

  document.addEventListener("visibilitychange", function () {
    if (document.hidden) {
      cancelAnimationFrame(raf);
    } else {
      draw();
    }
  });

  draw();
})();

// Lightbox
(function () {
  var lb = document.getElementById("lb");
  var lbImg = document.getElementById("lb-img");
  document.querySelectorAll(".shot img").forEach(function (img) {
    img.addEventListener("click", function () {
      lbImg.src = img.src;
      lbImg.alt = img.alt;
      lb.classList.add("open");
    });
  });
  lb.addEventListener("click", function (e) {
    if (e.target === lb || e.target.classList.contains("lb-close"))
      lb.classList.remove("open");
  });
  document.addEventListener("keydown", function (e) {
    if (e.key === "Escape") lb.classList.remove("open");
  });
})();
