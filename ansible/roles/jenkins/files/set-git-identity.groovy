import jenkins.model.Jenkins

def home = new File(Jenkins.getInstance().getRootDir(), ".gitconfig")
home.text = """[user]
    name = vannaboth
    email = vannaboth100@gmail.com
"""
