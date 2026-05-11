#!/usr/bin/env python3
"""
FM/DMB Repeater Monitor — PyQt5 Dark-Theme Dashboard

Connects to STM32 over UART, receives CSV data, and displays:
  - 6 gauge widgets (temperature, VSWR, RSSI x2, output power x2)
  - LED alarm indicators
  - 40 FM + 6 DMB channel tables
  - Event log with timestamps
  - Expert register read/write panel

Usage:
  python monitor_gui.py
"""

import sys
import csv
import time
import struct
from datetime import datetime
from collections import deque

from PyQt5.QtWidgets import (
    QApplication, QMainWindow, QWidget, QVBoxLayout, QHBoxLayout,
    QGridLayout, QLabel, QPushButton, QTabWidget, QTableWidget,
    QTableWidgetItem, QTextEdit, QLineEdit, QGroupBox, QFrame,
    QSplitter, QHeaderView, QCheckBox, QSpinBox, QPlainTextEdit,
    QScrollBar
)
from PyQt5.QtCore import (
    Qt, QTimer, QThread, pyqtSignal, QSize
)
from PyQt5.QtGui import (
    QPainter, QColor, QPen, QFont, QBrush, QPalette,
    QLinearGradient, QRadialGradient, QConicalGradient
)
import serial
import serial.tools.list_ports


# ==============================================================================
# Custom Gauge Widget
# ==============================================================================
class GaugeWidget(QWidget):
    """Analog gauge widget drawn with QPainter."""

    def __init__(self, title, unit, min_val, max_val, colors=None, parent=None):
        super().__init__(parent)
        self.title = title
        self.unit = unit
        self.min_val = min_val
        self.max_val = max_val
        self.value = min_val
        self.colors = colors or [(0, Qt.green), (50, QColor(255, 255, 0)),
                                 (80, QColor(255, 100, 0)), (100, Qt.red)]
        self.setMinimumSize(140, 160)

    def set_value(self, value):
        self.value = max(self.min_val, min(self.max_val, float(value)))
        self.update()

    def _interpolate_color(self, ratio):
        ratio = max(0.0, min(1.0, ratio))
        val = ratio * 100
        for threshold, color in self.colors:
            if val <= threshold:
                r, g, b, _ = color.getRgb()
                return QColor(r, g, b)
        r, g, b, _ = self.colors[-1][1].getRgb()
        return QColor(r, g, b)

    def paintEvent(self, event):
        painter = QPainter(self)
        painter.setRenderHint(QPainter.Antialiasing)

        w = self.width()
        h = self.height()
        cx, cy = w // 2, int(h * 0.65)
        radius = int(min(w, h * 1.2) * 0.38)

        # Background
        painter.setPen(Qt.NoPen)
        painter.setBrush(QColor(20, 20, 35))
        painter.drawRoundedRect(0, 0, w, h, 8, 8)

        # Arc background
        pen = QPen(QColor(50, 50, 70), 6)
        painter.setPen(pen)
        painter.drawArc(cx - radius, cy - radius, radius * 2, radius * 2,
                        225 * 16, 270 * 16)

        # Arc value
        ratio = (self.value - self.min_val) / (self.max_val - self.min_val)
        color = self._interpolate_color(ratio)
        pen.setColor(color)
        pen.setWidth(6)
        painter.setPen(pen)
        sweep = int(270 * ratio)
        painter.drawArc(cx - radius, cy - radius, radius * 2, radius * 2,
                        225 * 16, sweep * 16)

        # Needle
        angle = 225 + 270 * ratio
        rad = (angle - 90) * 3.14159 / 180.0
        nx = cx + int(radius * 0.75 * __import__('math').cos(rad))
        ny = cy + int(radius * 0.75 * __import__('math').sin(rad))
        painter.setPen(QPen(QColor(200, 200, 220), 2))
        painter.drawLine(cx, cy, nx, ny)

        # Center dot
        painter.setBrush(QColor(200, 200, 220))
        painter.drawEllipse(cx - 4, cy - 4, 8, 8)

        # Value text
        font = QFont("Arial", 14, QFont.Bold)
        painter.setFont(font)
        painter.setPen(QColor(200, 200, 220))
        text = f"{self.value:.1f}"
        painter.drawText(0, cy + 20, w, 30, Qt.AlignCenter, text)

        # Unit
        font.setPointSize(9)
        painter.setFont(font)
        painter.setPen(QColor(120, 120, 150))
        painter.drawText(0, cy + 45, w, 20, Qt.AlignCenter, self.unit)

        # Title
        font.setPointSize(10)
        painter.setFont(font)
        painter.setPen(QColor(160, 160, 190))
        painter.drawText(0, 10, w, 25, Qt.AlignCenter, self.title)


# ==============================================================================
# LED Indicator Widget
# ==============================================================================
class LedWidget(QFrame):
    """Small LED indicator (green/yellow/red)."""

    def __init__(self, label, parent=None):
        super().__init__(parent)
        self.label = label
        self.state = "green"
        self.setMinimumSize(60, 30)
        self.setMaximumSize(120, 35)

    def set_state(self, state):
        self.state = state
        self.update()

    def paintEvent(self, event):
        painter = QPainter(self)
        painter.setRenderHint(QPainter.Antialiasing)

        color_map = {
            "green": QColor(0, 200, 0),
            "yellow": QColor(255, 200, 0),
            "red": QColor(255, 50, 50),
            "gray": QColor(80, 80, 80)
        }
        color = color_map.get(self.state, color_map["gray"])

        # LED circle
        painter.setPen(Qt.NoPen)
        painter.setBrush(color)
        painter.drawEllipse(4, 4, 16, 16)

        # Glow effect
        glow = QRadialGradient(12, 12, 12)
        glow.setColorAt(0, QColor(color.red(), color.green(), color.blue(), 100))
        glow.setColorAt(1, QColor(color.red(), color.green(), color.blue(), 0))
        painter.setBrush(QBrush(glow))
        painter.drawEllipse(0, 0, 24, 24)

        # Label
        font = QFont("Arial", 8)
        painter.setFont(font)
        painter.setPen(QColor(200, 200, 220))
        painter.drawText(24, 0, self.width() - 24, 24, Qt.AlignVCenter, self.label)


# ==============================================================================
# Serial Communication Thread
# ==============================================================================
class SerialComm(QThread):
    """QThread for non-blocking serial port reading."""
    data_received = pyqtSignal(str)
    connection_status = pyqtSignal(bool)

    def __init__(self, port, baud=115200):
        super().__init__()
        self.port = port
        self.baud = baud
        self.ser = None
        self.running = False

    def connect_port(self):
        try:
            self.ser = serial.Serial(
                port=self.port, baudrate=self.baud, timeout=0.1,
                bytesize=serial.EIGHTBITS, parity=serial.PARITY_NONE,
                stopbits=serial.STOPBITS_ONE
            )
            self.running = True
            self.connection_status.emit(True)
            return True
        except serial.SerialException as e:
            self.connection_status.emit(False)
            return False

    def disconnect(self):
        self.running = False
        if self.ser and self.ser.is_open:
            self.ser.close()
        self.connection_status.emit(False)

    def send_command(self, cmd):
        if self.ser and self.ser.is_open:
            self.ser.write((cmd + '\n').encode())

    def run(self):
        if not self.ser or not self.ser.is_open:
            return

        buf = ""
        while self.running:
            try:
                if self.ser.in_waiting > 0:
                    data = self.ser.read(self.ser.in_waiting).decode('utf-8', errors='replace')
                    buf += data
                    while '\n' in buf:
                        line, buf = buf.split('\n', 1)
                        line = line.strip()
                        if line:
                            self.data_received.emit(line)
                else:
                    self.msleep(10)
            except serial.SerialException:
                self.connection_status.emit(False)
                break


# ==============================================================================
# Main Window
# ==============================================================================
class MainWindow(QMainWindow):
    """Main application window."""

    def __init__(self):
        super().__init__()
        self.setWindowTitle("FM/DMB Repeater Monitor")
        self.setMinimumSize(1100, 750)

        # Apply dark palette
        self._setup_dark_theme()

        # Central widget
        central = QWidget()
        self.setCentralWidget(central)
        main_layout = QVBoxLayout(central)
        main_layout.setContentsMargins(6, 6, 6, 6)
        main_layout.setSpacing(6)

        # Serial connection bar
        self._build_serial_bar(main_layout)

        # Content area
        splitter = QSplitter(Qt.Vertical)
        main_layout.addWidget(splitter)

        # Top: gauges + LEDs
        top_widget = QWidget()
        top_layout = QVBoxLayout(top_widget)
        top_layout.setContentsMargins(0, 0, 0, 0)
        self._build_gauge_section(top_layout)
        self._build_led_section(top_layout)
        splitter.addWidget(top_widget)

        # Bottom: tabs (channels, registers, log)
        tabs = QTabWidget()
        self._build_channel_tab(tabs)
        self._build_register_tab(tabs)
        self._build_log_tab(tabs)
        splitter.addWidget(tabs)

        splitter.setSizes([280, 400])

        # Timer for simulation mode (no serial)
        self.sim_timer = QTimer()
        self.sim_timer.timeout.connect(self._simulate_data)
        self.sim_timer.start(2000)

        # Status bar
        self.statusBar().showMessage("Disconnected (simulation mode)")

        # Store latest CSV values
        self.latest_values = {}

    def _setup_dark_theme(self):
        palette = QPalette()
        palette.setColor(QPalette.Window, QColor(26, 26, 46))
        palette.setColor(QPalette.WindowText, QColor(200, 200, 220))
        palette.setColor(QPalette.Base, QColor(20, 20, 40))
        palette.setColor(QPalette.AlternateBase, QColor(30, 30, 55))
        palette.setColor(QPalette.ToolTipBase, QColor(40, 40, 70))
        palette.setColor(QPalette.ToolTipText, QColor(200, 200, 220))
        palette.setColor(QPalette.Text, QColor(200, 200, 220))
        palette.setColor(QPalette.Button, QColor(35, 35, 60))
        palette.setColor(QPalette.ButtonText, QColor(200, 200, 220))
        palette.setColor(QPalette.BrightText, Qt.red)
        palette.setColor(QPalette.Link, QColor(100, 150, 255))
        palette.setColor(QPalette.Highlight, QColor(60, 100, 200))
        palette.setColor(QPalette.HighlightedText, Qt.white)
        QApplication.setPalette(palette)

        # Dark stylesheet for widgets
        self.setStyleSheet("""
            QToolTip { background-color: #282850; border: 1px solid #404070; }
            QGroupBox { border: 1px solid #404070; border-radius: 4px;
                        margin-top: 8px; font-weight: bold;
                        color: #A0A0D0; padding-top: 12px; }
            QGroupBox::title { subcontrol-origin: margin; left: 10px; }
            QTabWidget::pane { border: 1px solid #404070;
                               background-color: #1A1A2E; }
            QTabBar::tab { background-color: #252545; color: #8080A0;
                           padding: 6px 14px; margin-right: 2px; }
            QTabBar::tab:selected { background-color: #303060; color: #D0D0F0; }
            QTableWidget { gridline-color: #303050;
                           background-color: #1E1E38;
                           alternate-background-color: #262648; }
            QHeaderView::section { background-color: #2A2A50;
                                   color: #A0A0D0; border: 1px solid #404070;
                                   padding: 3px; }
            QTextEdit, QPlainTextEdit { background-color: #0E0E1E;
                                        color: #C0C0E0;
                                        border: 1px solid #404070; }
            QLineEdit { background-color: #1A1A30; color: #C0C0E0;
                        border: 1px solid #404070; padding: 3px; }
            QPushButton { background-color: #303060; color: #C0C0E0;
                          border: 1px solid #505090; padding: 4px 10px;
                          border-radius: 3px; }
            QPushButton:hover { background-color: #404080; }
            QPushButton:pressed { background-color: #202050; }
            QSpinBox { background-color: #1A1A30; color: #C0C0E0;
                       border: 1px solid #404070; }
        """)

    def _build_serial_bar(self, layout):
        bar = QHBoxLayout()
        bar.setSpacing(6)

        # Port selector
        bar.addWidget(QLabel("Port:"))
        self.port_combo = QLineEdit()
        self.port_combo.setPlaceholderText("COM3 or /dev/ttyACM0")
        self.port_combo.setMaximumWidth(150)
        bar.addWidget(self.port_combo)

        self.connect_btn = QPushButton("Connect")
        self.connect_btn.clicked.connect(self._toggle_serial)
        bar.addWidget(self.connect_btn)

        self.status_led = LedWidget("Serial")
        self.status_led.set_state("gray")
        bar.addWidget(self.status_led)

        bar.addStretch()
        layout.addLayout(bar)

    def _build_gauge_section(self, layout):
        gauge_layout = QHBoxLayout()
        gauge_layout.setSpacing(4)

        self.gauges = {}
        titles = [
            ("Temp", "C", 0, 100),
            ("VSWR", "ratio", 1.0, 5.0),
            ("RSSI FM", "dBm", -120, -30),
            ("RSSI DMB", "dBm", -120, -30),
            ("PWR FM", "W", 0, 50),
            ("PWR DMB", "W", 0, 50),
        ]
        for title, unit, vmin, vmax in titles:
            g = GaugeWidget(title, unit, vmin, vmax)
            gauge_layout.addWidget(g)
            self.gauges[title] = g

        layout.addLayout(gauge_layout)

    def _build_led_section(self, layout):
        led_layout = QHBoxLayout()
        led_layout.setSpacing(10)

        self.leds = {}
        for name in ["OT", "VSWR", "PA Fault", "FIFO Full", "Link"]:
            led = LedWidget(name)
            self.leds[name] = led
            led_layout.addWidget(led)

        led_layout.addStretch()
        layout.addLayout(led_layout)

    def _build_channel_tab(self, tabs):
        channel_widget = QWidget()
        layout = QHBoxLayout(channel_widget)

        # FM channels
        fm_group = QGroupBox("FM Channels (40)")
        fm_layout = QVBoxLayout(fm_group)
        self.fm_table = QTableWidget(40, 5)
        self.fm_table.setHorizontalHeaderLabels(["CH", "Freq (MHz)", "RSSI", "Gain", "AGC"])
        self.fm_table.verticalHeader().setVisible(False)
        self.fm_table.setAlternatingRowColors(True)
        self.fm_table.horizontalHeader().setStretchLastSection(True)
        self.fm_table.setEditTriggers(QTableWidget.NoEditTriggers)

        # Pre-fill channel numbers and default frequencies
        fm_freqs = [88.1 + i * 0.2 for i in range(40)]
        for row in range(40):
            self.fm_table.setItem(row, 0, QTableWidgetItem(str(row)))
            self.fm_table.setItem(row, 1, QTableWidgetItem(f"{fm_freqs[row]:.1f}"))
            self.fm_table.setItem(row, 2, QTableWidgetItem("-"))
            self.fm_table.setItem(row, 3, QTableWidgetItem("-"))
            self.fm_table.setItem(row, 4, QTableWidgetItem("-"))

        fm_layout.addWidget(self.fm_table)
        layout.addWidget(fm_group)

        # DMB channels
        dmb_group = QGroupBox("DMB Channels (6)")
        dmb_layout = QVBoxLayout(dmb_group)
        self.dmb_table = QTableWidget(6, 5)
        self.dmb_table.setHorizontalHeaderLabels(["CH", "Freq (MHz)", "RSSI", "Gain", "AGC"])
        self.dmb_table.verticalHeader().setVisible(False)
        self.dmb_table.setAlternatingRowColors(True)
        self.dmb_table.horizontalHeader().setStretchLastSection(True)
        self.dmb_table.setEditTriggers(QTableWidget.NoEditTriggers)

        dmb_freqs = [180.0 + i * 2.0 for i in range(6)]
        for row in range(6):
            self.dmb_table.setItem(row, 0, QTableWidgetItem(str(row)))
            self.dmb_table.setItem(row, 1, QTableWidgetItem(f"{dmb_freqs[row]:.1f}"))
            self.dmb_table.setItem(row, 2, QTableWidgetItem("-"))
            self.dmb_table.setItem(row, 3, QTableWidgetItem("-"))
            self.dmb_table.setItem(row, 4, QTableWidgetItem("-"))

        dmb_layout.addWidget(self.dmb_table)
        layout.addWidget(dmb_group)

        tabs.addTab(channel_widget, "Channels")

    def _build_register_tab(self, tabs):
        reg_widget = QWidget()
        layout = QVBoxLayout(reg_widget)

        # Read section
        read_layout = QHBoxLayout()
        read_layout.addWidget(QLabel("Address (hex):"))
        self.reg_addr = QLineEdit()
        self.reg_addr.setPlaceholderText("e.g. 60")
        self.reg_addr.setMaximumWidth(80)
        read_layout.addWidget(self.reg_addr)
        self.reg_read_btn = QPushButton("Read")
        read_layout.addWidget(self.reg_read_btn)
        self.reg_value = QLineEdit()
        self.reg_value.setReadOnly(True)
        self.reg_value.setMaximumWidth(120)
        read_layout.addWidget(self.reg_value)
        read_layout.addStretch()
        layout.addLayout(read_layout)

        # Write section
        write_layout = QHBoxLayout()
        write_layout.addWidget(QLabel("Write Value (hex):"))
        self.reg_wr_value = QLineEdit()
        self.reg_wr_value.setPlaceholderText("e.g. 00FF")
        self.reg_wr_value.setMaximumWidth(100)
        write_layout.addWidget(self.reg_wr_value)
        self.reg_write_btn = QPushButton("Write")
        write_layout.addWidget(self.reg_write_btn)
        write_layout.addStretch()
        layout.addLayout(write_layout)

        # Quick access buttons
        quick_layout = QHBoxLayout()
        quick_layout.addWidget(QLabel("Quick:"))
        for label, addr in [("Temp", "60"), ("VSWR", "61"), ("Alarm", "62"),
                             ("FWD PWR", "63"), ("REF PWR", "64")]:
            btn = QPushButton(label)
            btn.clicked.connect(lambda _, a=addr: self._quick_read(a))
            quick_layout.addWidget(btn)
        quick_layout.addStretch()
        layout.addLayout(quick_layout)

        layout.addStretch()
        tabs.addTab(reg_widget, "Registers")

    def _build_log_tab(self, tabs):
        log_widget = QWidget()
        layout = QVBoxLayout(log_widget)

        self.log_area = QPlainTextEdit()
        self.log_area.setReadOnly(True)
        self.log_area.setMaximumBlockCount(1000)
        self.log_area.setFont(QFont("Consolas", 9))

        # Bottom bar
        bar = QHBoxLayout()
        self.log_cb = QCheckBox("CSV Logging")
        bar.addWidget(self.log_cb)
        bar.addStretch()
        self.clear_log_btn = QPushButton("Clear")
        self.clear_log_btn.clicked.connect(self.log_area.clear)
        bar.addWidget(self.clear_log_btn)

        layout.addWidget(self.log_area)
        layout.addLayout(bar)

        tabs.addTab(log_widget, "Event Log")

    # ==========================================================================
    # Serial / Simulation
    # ==========================================================================
    def _toggle_serial(self):
        if hasattr(self, 'ser_comm') and self.ser_comm and self.ser_comm.running:
            self.ser_comm.disconnect()
            self.ser_comm.wait(1000)
            self.connect_btn.setText("Connect")
            self.status_led.set_state("gray")
            self.statusBar().showMessage("Disconnected")
            if self.sim_timer and not self.sim_timer.isActive():
                self.sim_timer.start(2000)
        else:
            port = self.port_combo.text().strip()
            if not port:
                self.statusBar().showMessage("Enter a serial port")
                return
            self.ser_comm = SerialComm(port)
            self.ser_comm.data_received.connect(self._on_serial_data)
            self.ser_comm.connection_status.connect(self._on_serial_status)
            if self.ser_comm.connect_port():
                self.ser_comm.start()
                self.connect_btn.setText("Disconnect")
                if self.sim_timer and self.sim_timer.isActive():
                    self.sim_timer.stop()
            else:
                self.statusBar().showMessage(f"Failed to connect {port}")

    def _on_serial_status(self, ok):
        if ok:
            self.status_led.set_state("green")
        else:
            self.status_led.set_state("red")

    def _on_serial_data(self, line):
        self.log_area.appendPlainText(f"[{datetime.now():%H:%M:%S}] RX: {line}")
        self._parse_csv(line)

    def _simulate_data(self):
        import random
        line = (f"TEMP,{25 + random.random() * 10:.1f},"
                f"VSWR,{1.0 + random.random() * 0.5:.2f},"
                f"RSSI_FM,{-70 + random.random() * 20:.1f},"
                f"RSSI_DMB,{-65 + random.random() * 15:.1f},"
                f"PWR_FM,{2 + random.random() * 3:.1f},"
                f"PWR_DMB,{1 + random.random() * 2:.1f},"
                f"ALARM,0")
        self._parse_csv(line)

    def _parse_csv(self, line):
        """Parse CSV-formatted telemetry data."""
        parts = line.replace(', ', ',').split(',')
        data = {}
        for i in range(0, len(parts) - 1, 2):
            data[parts[i].strip()] = parts[i + 1].strip()

        # Update gauges
        if 'TEMP' in data:
            self.gauges['Temp'].set_value(data['TEMP'])
        if 'VSWR' in data:
            self.gauges['VSWR'].set_value(data['VSWR'])
        if 'RSSI_FM' in data:
            self.gauges['RSSI FM'].set_value(data['RSSI_FM'])
        if 'RSSI_DMB' in data:
            self.gauges['RSSI DMB'].set_value(data['RSSI_DMB'])
        if 'PWR_FM' in data:
            self.gauges['PWR FM'].set_value(data['PWR_FM'])
        if 'PWR_DMB' in data:
            self.gauges['PWR DMB'].set_value(data['PWR_DMB'])

        # Update LEDs
        alarm = int(data.get('ALARM', '0'))
        self.leds['OT'].set_state("red" if alarm & 0x01 else "green")
        self.leds['VSWR'].set_state("red" if alarm & 0x02 else "green")
        self.leds['PA Fault'].set_state("red" if alarm & 0x04 else "green")
        self.leds['FIFO Full'].set_state("yellow" if alarm & 0x08 else "green")
        self.leds['Link'].set_state("green" if alarm & 0x10 else "yellow")

        # Update channel tables (if we have per-channel data)
        # Format: FM_CH0_RSSI, FM_CH0_GAIN, FM_CH0_AGC, FM_CH1_RSSI, ...

        # Log if enabled
        if self.log_cb.isChecked():
            with open("repeater_log.csv", "a") as f:
                f.write(f"{datetime.now().isoformat()},{line}\n")

        self.latest_values = data

    def _quick_read(self, addr):
        self.reg_addr.setText(addr)
        if hasattr(self, 'ser_comm') and self.ser_comm and self.ser_comm.running:
            self.ser_comm.send_command(f"rd {addr}")
        else:
            self.reg_value.setText("--")


# ==============================================================================
# Entry Point
# ==============================================================================
def main():
    app = QApplication(sys.argv)
    window = MainWindow()
    window.show()
    sys.exit(app.exec_())


if __name__ == "__main__":
    main()
