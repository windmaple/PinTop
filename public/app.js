/**
 * PinTop — Interactive Static Website Logic
 * Handles the live macOS Window-Pinning Sandbox, 4 Hybrid Modes,
 * Screenshot Switcher, Checksum/CLI Copy, and Download Toast.
 */

(function () {
  'use strict';

  // 1. Sticky Header Scroll Shadow
  const siteHeader = document.getElementById('site-header');
  window.addEventListener('scroll', () => {
    if (window.scrollY > 12) {
      siteHeader.classList.add('scrolled');
    } else {
      siteHeader.classList.remove('scrolled');
    }
  }, { passive: true });

  // 2. Download Buttons & Post-Download Helper Toast
  const downloadToast = document.getElementById('download-toast');
  const toastCloseBtn = document.getElementById('toast-close-btn');
  const downloadBtnIds = [
    'nav-download-btn',
    'hero-download-btn',
    'footer-download-btn',
    'footer-link-download'
  ];

  let toastTimer = null;
  function showDownloadToast() {
    if (!downloadToast) return;
    downloadToast.classList.add('visible');
    if (toastTimer) clearTimeout(toastTimer);
    toastTimer = setTimeout(() => {
      downloadToast.classList.remove('visible');
    }, 9000);
  }

  downloadBtnIds.forEach((id) => {
    const el = document.getElementById(id);
    if (el) {
      el.addEventListener('click', () => {
        showDownloadToast();
      });
    }
  });

  if (toastCloseBtn && downloadToast) {
    toastCloseBtn.addEventListener('click', () => {
      downloadToast.classList.remove('visible');
    });
  }

  // 3. Copy SHA-256 Checksum & Build Commands
  const copyChecksumBtn = document.getElementById('copy-checksum-btn');
  const checksumCopyLabel = document.getElementById('checksum-copy-label');

  if (copyChecksumBtn && checksumCopyLabel) {
    copyChecksumBtn.addEventListener('click', async () => {
      const hash = copyChecksumBtn.getAttribute('data-checksum') || '';
      try {
        await navigator.clipboard.writeText(hash);
        checksumCopyLabel.textContent = '✓ Copied!';
        setTimeout(() => {
          checksumCopyLabel.textContent = 'Copy';
        }, 2200);
      } catch (_) {
        checksumCopyLabel.textContent = 'Copied';
      }
    });
  }

  const copyBuildBtn = document.getElementById('copy-build-cmd-btn');
  if (copyBuildBtn) {
    const buildScript = [
      'git clone https://github.com/windmaple/PinTop.git',
      'cd PinTop',
      'chmod +x build_app.sh',
      './build_app.sh',
      'open PinTop.app'
    ].join('\n');

    copyBuildBtn.addEventListener('click', async () => {
      try {
        await navigator.clipboard.writeText(buildScript);
        const original = copyBuildBtn.textContent;
        copyBuildBtn.textContent = '✓ Copied to Clipboard';
        setTimeout(() => {
          copyBuildBtn.textContent = original;
        }, 2200);
      } catch (_) {
        copyBuildBtn.textContent = 'Copied';
      }
    });
  }

  // 4. Interactive Live macOS Window-Pinning Sandbox
  const desktopStage = document.getElementById('desktop-stage');
  const pinnedWindow = document.getElementById('sim-window-pinned');
  const editorWindow = document.getElementById('sim-window-editor');
  const controlPill = document.getElementById('sim-control-pill');
  const pillModeLabel = document.getElementById('pill-mode-label');
  const pillOpacityLabel = document.getElementById('pill-opacity-label');
  const opacitySlider = document.getElementById('sandbox-opacity-slider');
  const opacityValueText = document.getElementById('sandbox-opacity-value');
  const overlapBtn = document.getElementById('sandbox-overlap-btn');
  const pickerBtn = document.getElementById('sandbox-picker-btn');
  const statusMessage = document.getElementById('sandbox-status-message');
  const stateBadge = document.getElementById('sim-state-badge');
  const chromeDesc = document.getElementById('sim-chrome-desc');
  const menubarPinBadge = document.getElementById('menubar-pin-badge');

  // Code tokens inside the simulated Xcode/VS Code editor
  const codeModeToken = document.getElementById('code-mode-token');
  const codeOpacityToken = document.getElementById('code-opacity-token');
  const codeObstructedToken = document.getElementById('code-obstructed-token');

  // Interactive counters inside the simulated windows
  const chromeClickBtn = document.getElementById('sim-chrome-click-btn');
  const chromeClickCountEl = document.getElementById('chrome-click-count');
  const editorClickBtn = document.getElementById('sim-editor-click-btn');
  const editorClickCountEl = document.getElementById('editor-click-count');

  let currentMode = 'inPlace'; // 'inPlace' | 'ghost' | 'pip' | 'autoRaise'
  let currentOpacity = 100;
  let isOverlapped = false;
  let isCrosshairPicker = false;
  let isPinned = true;
  let chromeClicks = 0;
  let editorClicks = 0;

  if (chromeClickBtn && chromeClickCountEl) {
    chromeClickBtn.addEventListener('click', (e) => {
      e.stopPropagation();
      chromeClicks += 1;
      chromeClickCountEl.textContent = String(chromeClicks);
    });
  }

  if (editorClickBtn && editorClickCountEl) {
    editorClickBtn.addEventListener('click', (e) => {
      e.stopPropagation();
      editorClicks += 1;
      editorClickCountEl.textContent = String(editorClicks);
    });
  }

  function rectsIntersect(r1, r2) {
    return !(
      r2.left > r1.right - 24 ||
      r2.right < r1.left + 24 ||
      r2.top > r1.bottom - 24 ||
      r2.bottom < r1.top + 24
    );
  }

  function checkOverlapState() {
    if (!pinnedWindow || !editorWindow) return false;
    const pRect = pinnedWindow.getBoundingClientRect();
    const eRect = editorWindow.getBoundingClientRect();
    return rectsIntersect(pRect, eRect);
  }

  function updateSandboxPresentation() {
    if (!pinnedWindow || !editorWindow || !controlPill) return;

    isOverlapped = checkOverlapState();
    if (codeObstructedToken) {
      codeObstructedToken.textContent = isOverlapped ? 'true' : 'false';
    }

    if (!isPinned) {
      controlPill.style.opacity = '0';
      controlPill.style.pointerEvents = 'none';
      pinnedWindow.style.zIndex = '15';
      pinnedWindow.style.opacity = '1';
      menubarPinBadge.textContent = '📌 PinTop (0)';
      stateBadge.textContent = 'Unpinned';
      statusMessage.innerHTML = '<strong>All Windows Unpinned (⌃⌥U):</strong> Chrome now behaves like a standard window and can be covered by other apps.';
      return;
    }

    controlPill.style.opacity = '1';
    controlPill.style.pointerEvents = 'auto';
    pinnedWindow.style.zIndex = '30';
    menubarPinBadge.textContent = '📌 1 Pinned';

    // Reset mode classes
    pinnedWindow.classList.remove('mode-pip', 'mode-ghost');
    controlPill.classList.remove('pip-pos');

    const normalizedOpacity = (currentOpacity / 100).toFixed(2);
    pinnedWindow.style.opacity = String(currentOpacity / 100);
    pillOpacityLabel.textContent = `${currentOpacity}%`;
    opacityValueText.textContent = `${currentOpacity}%`;
    if (codeOpacityToken) {
      codeOpacityToken.textContent = normalizedOpacity;
    }

    if (currentMode === 'inPlace') {
      pillModeLabel.textContent = '1:1 Pin';
      if (codeModeToken) codeModeToken.textContent = '.inPlace';

      if (isOverlapped) {
        stateBadge.textContent = '60fps IOSurface Mirror';
        chromeDesc.textContent = 'Overlap detected! PinTop is projecting a 60fps zero-copy IOSurface mirror above the code editor so Chrome stays 100% visible.';
        statusMessage.innerHTML = '<strong>1:1 Pin (Obstructed):</strong> Editor overlaps Chrome, so PinTop seamlessly activates the 60fps floating mirror on top.';
      } else {
        stateBadge.textContent = 'Native Interactive';
        chromeDesc.textContent = 'When unobstructed, you interact directly with the real Chrome window. When overlapped by another app, PinTop projects a 60fps zero-copy mirror on top.';
        statusMessage.innerHTML = '<strong>1:1 Pin (Uncovered):</strong> Native window is unobstructed and receives all clicks, scrolling, and keyboard input directly.';
      }
    } else if (currentMode === 'ghost') {
      pinnedWindow.classList.add('mode-ghost');
      pillModeLabel.textContent = 'Ghost';
      if (codeModeToken) codeModeToken.textContent = '.ghost';
      stateBadge.textContent = `Click-Through (${currentOpacity}%)`;
      chromeDesc.textContent = 'Ghost mode sets ignoresMouseEvents = true. Even when Chrome floats right over the code editor, your clicks pass straight through to the editor underneath!';
      statusMessage.innerHTML = '<strong>Ghost Mode Active (⌃⌥G):</strong> Try clicking "Test Editor Click" even while Chrome overlaps it—clicks pass right through the translucent window!';
    } else if (currentMode === 'pip') {
      pinnedWindow.classList.add('mode-pip');
      controlPill.classList.add('pip-pos');
      pillModeLabel.textContent = 'PiP';
      if (codeModeToken) codeModeToken.textContent = '.pip';
      stateBadge.textContent = 'Floating Mini PiP';
      chromeDesc.textContent = 'Picture-in-Picture mode scales the live 60fps window stream into a compact corner monitor so you have full room to code.';
      statusMessage.innerHTML = '<strong>PiP Mode Active:</strong> Target window is scaled into a draggable, aspect-locked floating mini monitor.';
    } else if (currentMode === 'autoRaise') {
      pillModeLabel.textContent = 'Auto-Raise';
      if (codeModeToken) codeModeToken.textContent = '.autoRaise';
      stateBadge.textContent = 'AXUIElement Raised';
      chromeDesc.textContent = 'Auto-Raise watches window Z-order and uses macOS Accessibility APIs to raise the native window whenever another app tries to cover it.';
      statusMessage.innerHTML = '<strong>Auto-Raise Mode Active:</strong> Whenever an overlapping window is detected, PinTop automatically raises the native window to the front.';
    }
  }

  function setSandboxMode(newMode) {
    isPinned = true;
    currentMode = newMode;

    // Match native PinTop behavior from PinnedWindowController.swift:
    // Switching to Ghost defaults opacity to 78%; switching out restores 100%
    if (newMode === 'ghost' && currentOpacity > 95) {
      currentOpacity = 78;
      if (opacitySlider) opacitySlider.value = '78';
    } else if (newMode !== 'ghost' && currentOpacity === 78) {
      currentOpacity = 100;
      if (opacitySlider) opacitySlider.value = '100';
    }

    const modeButtons = document.querySelectorAll('.mode-switch-btn');
    modeButtons.forEach((btn) => {
      const isMatch = btn.getAttribute('data-mode') === newMode;
      btn.classList.toggle('active', isMatch);
      btn.setAttribute('aria-selected', isMatch ? 'true' : 'false');
    });

    updateSandboxPresentation();
  }

  // Bind mode tab buttons
  document.querySelectorAll('.mode-switch-btn').forEach((btn) => {
    btn.addEventListener('click', () => {
      const targetMode = btn.getAttribute('data-mode');
      if (targetMode) setSandboxMode(targetMode);
    });
  });

  // Bind opacity slider
  if (opacitySlider) {
    opacitySlider.addEventListener('input', (e) => {
      currentOpacity = parseInt(e.target.value, 10) || 100;
      updateSandboxPresentation();
    });
  }

  // Bind Toggle Overlap button
  let overlapToggleState = false;
  if (overlapBtn && editorWindow) {
    overlapBtn.addEventListener('click', () => {
      overlapToggleState = !overlapToggleState;
      if (overlapToggleState) {
        editorWindow.style.left = '140px';
        editorWindow.style.top = '88px';
      } else {
        editorWindow.style.left = '460px';
        editorWindow.style.top = '96px';
      }
      setTimeout(updateSandboxPresentation, 340);
    });
  }

  // Bind Crosshair Picker button (⌃⌥K simulation)
  if (pickerBtn && desktopStage) {
    pickerBtn.addEventListener('click', () => {
      isCrosshairPicker = !isCrosshairPicker;
      desktopStage.classList.toggle('crosshair-mode', isCrosshairPicker);
      pickerBtn.classList.toggle('picker-active', isCrosshairPicker);
      if (isCrosshairPicker) {
        statusMessage.innerHTML = '<strong>Crosshair Picker Active (⌃⌥K):</strong> Hover over any window on the desktop stage to highlight its frame, then click to pin it!';
      } else {
        updateSandboxPresentation();
      }
    });
  }

  // Clicking a window when Crosshair Picker is active
  [pinnedWindow, editorWindow].forEach((winEl) => {
    if (!winEl) return;
    winEl.addEventListener('click', () => {
      if (isCrosshairPicker && desktopStage && pickerBtn) {
        isCrosshairPicker = false;
        desktopStage.classList.remove('crosshair-mode');
        pickerBtn.classList.remove('picker-active');
        isPinned = true;
        updateSandboxPresentation();
        statusMessage.innerHTML = '<strong>Window Pinned via Crosshair Picker (⌃⌥K)!</strong> Target window is now locked on top.';
      }
    });
  });

  // Make the Editor Window draggable inside the desktop stage
  if (editorWindow && desktopStage) {
    let isDragging = false;
    let startX = 0;
    let startY = 0;
    let initialLeft = 0;
    let initialTop = 0;

    editorWindow.addEventListener('pointerdown', (e) => {
      if (e.target.closest('button') || isCrosshairPicker) return;
      isDragging = true;
      editorWindow.classList.add('dragging');
      startX = e.clientX;
      startY = e.clientY;
      initialLeft = editorWindow.offsetLeft;
      initialTop = editorWindow.offsetTop;
      editorWindow.setPointerCapture(e.pointerId);
    });

    editorWindow.addEventListener('pointermove', (e) => {
      if (!isDragging) return;
      const dx = e.clientX - startX;
      const dy = e.clientY - startY;
      const maxLeft = desktopStage.clientWidth - 120;
      const maxTop = desktopStage.clientHeight - 90;
      const nextLeft = Math.max(12, Math.min(maxLeft, initialLeft + dx));
      const nextTop = Math.max(36, Math.min(maxTop, initialTop + dy));
      editorWindow.style.left = `${nextLeft}px`;
      editorWindow.style.top = `${nextTop}px`;
      updateSandboxPresentation();
    });

    const stopDrag = () => {
      if (!isDragging) return;
      isDragging = false;
      editorWindow.classList.remove('dragging');
      updateSandboxPresentation();
    };

    editorWindow.addEventListener('pointerup', stopDrag);
    editorWindow.addEventListener('pointercancel', stopDrag);
  }

  // 5. Screenshot Tab Switcher
  const tabBtns = document.querySelectorAll('.screenshot-tab-btn');
  const activeScreenshotImg = document.getElementById('active-screenshot-img');
  const screenshotCaptionText = document.getElementById('screenshot-caption-text');

  tabBtns.forEach((btn) => {
    btn.addEventListener('click', () => {
      tabBtns.forEach((b) => b.classList.remove('active'));
      btn.classList.add('active');
      const imgSrc = btn.getAttribute('data-img');
      const caption = btn.getAttribute('data-caption');
      if (activeScreenshotImg && imgSrc) {
        activeScreenshotImg.src = imgSrc;
      }
      if (screenshotCaptionText && caption) {
        screenshotCaptionText.textContent = caption;
      }
    });
  });

  // 6. Global Keyboard Shortcut Cards Interactive Preview
  const shortcutCards = document.querySelectorAll('.shortcut-card');
  shortcutCards.forEach((card) => {
    card.addEventListener('click', () => {
      const key = card.getAttribute('data-hotkey');
      shortcutCards.forEach((c) => c.classList.remove('active-hotkey'));
      card.classList.add('active-hotkey');

      if (key === 'P') {
        isPinned = !isPinned;
        updateSandboxPresentation();
      } else if (key === 'K' && pickerBtn) {
        pickerBtn.click();
      } else if (key === 'G') {
        setSandboxMode(currentMode === 'ghost' ? 'inPlace' : 'ghost');
      } else if (key === 'U') {
        isPinned = false;
        updateSandboxPresentation();
      }

      const sandboxSection = document.getElementById('interactive-sandbox');
      if (sandboxSection) {
        sandboxSection.scrollIntoView({ behavior: 'smooth', block: 'center' });
      }
    });
  });

  // Initialize sandbox state
  updateSandboxPresentation();
})();
