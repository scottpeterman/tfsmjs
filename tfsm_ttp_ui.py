import sys
import traceback

from PyQt6.QtWidgets import (QApplication, QMainWindow, QWidget, QVBoxLayout,
                             QHBoxLayout, QLabel, QPlainTextEdit, QPushButton,
                             QComboBox, QDialog)
from templanator.highlighters import TTPHighlighter, TextFSMHighlighter
from templanator.dialogs.stubs import TTPWizardDialog, NapalmDialog, DBToolDialog, TTPFireDialog, TFSMFireDialog
from templanator.engines import Jinja2Engine, TemplateEngine


class TextFSMEngine(TemplateEngine):
    def process(self, source: str, template: str) -> tuple[bool, str]:
        try:
            import textfsm
            from io import StringIO

            # Parse template
            template_file = StringIO(template)
            fsm = textfsm.TextFSM(template_file)

            # Parse input text
            result = fsm.ParseText(source)

            # Format output
            output = "Header: " + str(fsm.header) + "\n\nData:\n"
            for row in result:
                output += str(row) + "\n"

            return True, output
        except Exception as e:
            return False, f"TextFSM Error: {str(e)}"

    def get_example(self) -> tuple[str, str]:
        source = """Interface                  IP-Address      OK? Method Status                Protocol
FastEthernet0/0            192.168.1.1     YES NVRAM  up                    up      
FastEthernet0/1            unassigned      YES NVRAM  administratively down down    
FastEthernet0/2            192.168.2.1     YES NVRAM  up                    up"""

        template = """Value Interface (\S+)
Value IP_Address (\S+)
Value OK (\S+)
Value Method (\S+)
Value Status (.+?)
Value Protocol (\S+)

Start
  ^${Interface}\s+${IP_Address}\s+${OK}\s+${Method}\s+${Status}\s+${Protocol}\s*$$ -> Record"""

        return source, template


class TTPEngine(TemplateEngine):
    def process(self, source: str, template: str) -> tuple[bool, str]:
        try:
            from ttp import ttp
            try:
                parser = ttp(data=source, template=template)
                parser.parse()
            except Exception as e:
                traceback.print_exc()
                return (False,  str(e))
            results = parser.result(format='json')[0]
            import json
            return True, json.dumps(json.loads(results), indent=2)
        except Exception as e:
            return False, f"TTP Error: {str(e)}"

    def get_example(self) -> tuple[str, str]:
        source = """Interface                  IP-Address      OK? Method Status                Protocol
FastEthernet0/0            192.168.1.1     YES NVRAM  up                    up      
FastEthernet0/1            unassigned      YES NVRAM  administratively down down    
FastEthernet0/2            192.168.2.1     YES NVRAM  up                    up"""

        template = """
<group name="interfaces">
Interface {{ interface }}  {{ ip }}     {{ ok }} {{ method }}  {{ status }}                    {{ protocol }}
</group>"""

        return source, template


class TemplateTester(QMainWindow):
    def __init__(self):
        super().__init__()
        self.init_ui()
        self.create_menus()
        self.init_template_engines()
        self.current_highlighter = None

    def init_template_engines(self):
        """Initialize available template engines"""
        # Create engine instances
        textfsm_engine = TextFSMEngine()
        ttp_engine = TTPEngine()
        jinja2_engine = Jinja2Engine()

        # Initialize traditional engines dict for compatibility
        self.engines = {
            'TextFSM_Table': textfsm_engine,
            'TextFSM_Detail': textfsm_engine,
            'TTP_Table': ttp_engine,
            'TTP_Detail': ttp_engine,
            'Jinja2': jinja2_engine
        }

        # Map combo box items to engines and their example types
        self.engine_map = {
            'TextFSM_Table': ('textfsm', textfsm_engine, 'table'),
            'TextFSM_Detail': ('textfsm', textfsm_engine, 'detail'),
            'TTP_Table': ('ttp', ttp_engine, 'table'),
            'TTP_Detail': ('ttp', ttp_engine, 'detail'),
            'Jinja2': ('jinja2', jinja2_engine, None)
        }

        # Update mode combo box
        self.mode_combo.clear()
        self.mode_combo.addItems(self.engines.keys())
        self.mode_combo.currentTextChanged.connect(self.on_mode_changed)

    def init_ui(self):
        """Initialize the user interface"""
        self.setWindowTitle("Template Engine Tester")
        self.setGeometry(100, 100, 600, 400)

        # Create central widget and layout
        central_widget = QWidget()
        self.setCentralWidget(central_widget)
        main_layout = QHBoxLayout(central_widget)

        # Left panel (Source and Template)
        left_panel = QWidget()
        left_layout = QVBoxLayout(left_panel)

        # Source section
        source_label = QLabel("Source")
        self.source_text = QPlainTextEdit()
        left_layout.addWidget(source_label)
        left_layout.addWidget(self.source_text)

        # Template section
        template_label = QLabel("Template")
        self.template_text = QPlainTextEdit()
        left_layout.addWidget(template_label)
        left_layout.addWidget(self.template_text)

        # Button bar
        button_layout = QHBoxLayout()

        self.render_button = QPushButton("Render")
        self.render_button.clicked.connect(self.render_template)
        self.render_button.setStyleSheet("background-color: #4CAF50; color: white;")

        self.clear_button = QPushButton("Clear")
        self.clear_button.clicked.connect(self.clear_fields)
        self.clear_button.setStyleSheet("background-color: #CD853F; color: white;")

        self.example_button = QPushButton("Example")
        self.example_button.clicked.connect(self.load_example)

        self.mode_combo = QComboBox()

        button_layout.addWidget(self.render_button)
        button_layout.addWidget(self.clear_button)
        button_layout.addWidget(self.example_button)
        button_layout.addWidget(self.mode_combo)
        button_layout.addStretch()

        left_layout.addLayout(button_layout)

        # Right panel (Result)
        right_panel = QWidget()
        right_layout = QVBoxLayout(right_panel)

        result_label = QLabel("Result")
        self.result_text = QPlainTextEdit()
        self.result_text.setReadOnly(True)

        right_layout.addWidget(result_label)
        right_layout.addWidget(self.result_text)

        # Add panels to main layout
        main_layout.addWidget(left_panel)
        main_layout.addWidget(right_panel)
        main_layout.setStretch(0, 1)
        main_layout.setStretch(1, 1)

        # Set dark theme
        self.apply_dark_theme()

    def apply_dark_theme(self):
        """Apply dark theme styling"""
        self.setStyleSheet("""
            QMainWindow, QWidget {
                background-color: #2b2b2b;
            }
            QLabel {
                color: white;
            }
            QPlainTextEdit {
                background-color: #1e1e1e;
                color: white;
                border: 1px solid #3c3c3c;
                font-family: monospace;
            }
            QPushButton {
                padding: 5px 15px;
                border-radius: 3px;
            }
            QComboBox {
                background-color: #3c3c3c;
                color: white;
                padding: 5px;
                border: 1px solid #505050;
            }
        """)

    def render_template(self):
        """Process the template using the selected engine"""
        current_mode = self.mode_combo.currentText()
        if current_mode not in self.engine_map:
            self.result_text.setPlainText("Error: No template engine selected")
            return

        engine_type, engine, _ = self.engine_map[current_mode]

        success, result = engine.process(
            self.source_text.toPlainText(),
            self.template_text.toPlainText()
        )

        # Clear any existing highlighter
        if self.current_highlighter:
            self.current_highlighter.setDocument(None)
            self.current_highlighter = None

        self.result_text.setPlainText(result)

        # Apply appropriate syntax highlighter
        if engine_type == 'ttp':
            self.current_highlighter = TTPHighlighter(self.result_text.document())
        elif engine_type == 'textfsm':
            self.current_highlighter = TextFSMHighlighter(self.result_text.document())

    def clear_fields(self):
        """Clear template and result fields, preserve source"""
        self.template_text.clear()
        self.result_text.clear()

    def load_example(self):
        """Load example for the current template engine"""
        current_mode = self.mode_combo.currentText()
        if not current_mode:
            return

        engine_type, engine, format_type = self.engine_map[current_mode]

        if engine_type in ('textfsm', 'ttp'):
            from templanator.cdp_examples import CDPExamples
            source, template = CDPExamples.get_example(CDPExamples,format_type, engine_type)
        else:  # Jinja2
            source, template = engine.get_example()

        self.source_text.setPlainText(source)
        self.template_text.setPlainText(template)

        # Clear result field when loading new example
        self.result_text.clear()

        # Clear any existing highlighter
        if self.current_highlighter:
            self.current_highlighter.setDocument(None)
            self.current_highlighter = None

    def on_mode_changed(self, mode: str):
        """Handle mode change"""
        # Only clear template and result, preserve source
        self.template_text.clear()
        self.result_text.clear()

        # Clear any existing highlighter
        if self.current_highlighter:
            self.current_highlighter.setDocument(None)
            self.current_highlighter = None


    def create_menus(self):
        """Create the menu bar and menus"""
        menubar = self.menuBar()

        # Tools menu
        tools_menu = menubar.addMenu('Tools')

        # Add tool actions
        tools = {
            'TTP Wizard': TTPWizardDialog,
            'Napalm Tool': NapalmDialog,
            'DB Tool': DBToolDialog,
            'TTP Fire': TTPFireDialog,
            'TFSM Fire': TFSMFireDialog
        }

        for tool_name, dialog_class in tools.items():
            action = tools_menu.addAction(tool_name)
            action.triggered.connect(lambda checked, d=dialog_class: self.show_tool_dialog(d))

        def show_tool_dialog(self, dialog_class):
            """Show the selected tool dialog"""
            dialog = dialog_class(self)
            dialog.exec()


if __name__ == '__main__':
    app = QApplication(sys.argv)
    window = TemplateTester()
    window.show()
    sys.exit(app.exec())