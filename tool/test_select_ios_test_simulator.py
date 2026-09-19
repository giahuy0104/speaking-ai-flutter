import unittest

from select_ios_test_simulator import select_destination


class SimulatorSelectionTest(unittest.TestCase):
    identifier = "12345678-1234-1234-1234-123456789ABC"

    def destination(self, arch="x86_64", name="iPhone 16"):
        return (
            "{ platform:iOS Simulator, arch:" + arch
            + ", id:" + self.identifier + ", OS:26.0, name:" + name + " }"
        )

    def test_selects_intel_after_arm(self):
        output = self.destination("arm64") + "\n" + self.destination()
        self.assertEqual(select_destination(output), self.identifier)

    def test_rejects_arm_only(self):
        with self.assertRaises(ValueError):
            select_destination(self.destination("arm64"))

    def test_rejects_ineligible_destination(self):
        with self.assertRaises(ValueError):
            select_destination("Ineligible destinations for Runner:\n" + self.destination())

    def test_rejects_ipad(self):
        with self.assertRaises(ValueError):
            select_destination(self.destination(name="iPad Pro"))

    def test_rejects_placeholder(self):
        with self.assertRaises(ValueError):
            select_destination(self.destination().replace(self.identifier, "placeholder"))


if __name__ == "__main__":
    unittest.main()
